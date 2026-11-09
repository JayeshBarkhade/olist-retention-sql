#!/usr/bin/env python3
"""Benchmark 4 queries with EXPLAIN (ANALYZE, BUFFERS) before and after creating the indexes in 04_indexes.sql.
Each query is run once to warm the cache, then 7 times; the MEDIAN execution time is reported.
Connection settings come from the usual PG* environment variables."""
import pathlib, re, statistics, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLANS = ROOT / "results" / "plans"
PLANS.mkdir(parents=True, exist_ok=True)
RUNS = 7


def psql(sql):
    r = subprocess.run(["psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", sql],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"psql failed:\n{r.stderr}\nSQL: {sql[:200]}")
    return r.stdout


index_sql = (ROOT / "04_optimization" / "04_indexes.sql").read_text()
index_names = re.findall(r"CREATE INDEX IF NOT EXISTS (\w+)", index_sql)

pid = psql("SELECT product_id FROM (SELECT product_id, count(*) n FROM olist.order_items GROUP BY 1) t "
           "ORDER BY abs(n - 150), product_id LIMIT 1").strip()
uid = psql("SELECT customer_unique_id FROM olist.customers GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1").strip()
QUERIES = {
 "A_customer_history": ("Order history of one customer (join customers -> orders -> items)",
   f"""SELECT o.order_id, o.purchase_ts, o.order_status, sum(i.price + i.freight_value) AS gmv
       FROM olist.customers c JOIN olist.orders o ON o.customer_id = c.customer_id
       LEFT JOIN olist.order_items i ON i.order_id = o.order_id
       WHERE c.customer_unique_id = '{uid}'
       GROUP BY o.order_id, o.purchase_ts, o.order_status ORDER BY o.purchase_ts"""),
 "B_daily_revenue_week": ("Daily revenue for one week (date-range filter on delivered orders)",
   """SELECT date_trunc('day', o.purchase_ts)::date AS day, count(DISTINCT o.order_id) AS orders, sum(i.price) AS revenue
      FROM olist.orders o JOIN olist.order_items i ON i.order_id = o.order_id
      WHERE o.order_status = 'delivered' AND o.purchase_ts >= '2018-06-01' AND o.purchase_ts < '2018-06-08'
      GROUP BY 1 ORDER BY 1"""),
 "E_single_product": ("Units and revenue for ONE product (e.g. a product page)",
   f"""SELECT count(*) AS units, sum(price) AS revenue, min(shipping_limit_date) AS first_ship_limit
       FROM olist.order_items WHERE product_id = '{pid}'"""),
 "C_q06_late_vs_repeat": ("Q6: late delivery vs repeat purchase (full analytical query)",
   (ROOT / "03_analysis" / "q06_late_delivery_vs_repeat.sql").read_text().rstrip().rstrip(";")),
 "D_q10_top_products": ("Q10: top 3 products per category (LATERAL)",
   (ROOT / "03_analysis" / "q10_top_products_per_category.sql").read_text().rstrip().rstrip(";")),
}


def run_one(sql):
    times, plan = [], ""
    for i in range(RUNS + 1):
        plan = psql("EXPLAIN (ANALYZE, BUFFERS)\n" + sql)
        t = float(re.search(r"Execution Time: ([\d.]+) ms", plan).group(1))
        if i > 0:
            times.append(t)
    return statistics.median(times), plan


def measure(label):
    res = {}
    for key, (desc, sql) in QUERIES.items():
        med, plan = run_one(sql)
        (PLANS / f"{label}_{key}.txt").write_text(plan)
        res[key] = (med, plan)
        print(f"      {label:6s} {key:24s} {med:9.1f} ms")
    return res


for n in index_names:
    psql(f"DROP INDEX IF EXISTS olist.{n}")
psql("ANALYZE")
before = measure("before")
psql(index_sql)
after = measure("after")

lines = ["# EXPLAIN ANALYZE: before vs after indexing", "",
         f"Median of {RUNS} runs (after 1 warm-up run), all data cached in memory, PostgreSQL "
         f"{psql('SHOW server_version').strip().split()[0]}. Full plans are in `results/plans/`.", "",
         "| Query | Before (ms) | After (ms) | Speed-up | Indexes used after |", "|---|---:|---:|---:|---|"]
for key, (desc, _) in QUERIES.items():
    b, a = before[key][0], after[key][0]
    used = sorted(set(re.findall(r"idx_\w+", after[key][1])))
    lines.append(f"| {desc} | {b:,.1f} | {a:,.1f} | {b / a:,.1f}x | {', '.join(used) or '(none: planner kept seq scan)'} |")
lines += ["", "Indexes created: " + ", ".join(f"`{n}`" for n in index_names), ""]
(ROOT / "results" / "explain_before_after.md").write_text("\n".join(lines))
print("      wrote results/explain_before_after.md")
