#!/usr/bin/env python3
"""Independent cross-check: recompute key SQL results from the RAW CSVs with pandas (different code path,
different engine) and compare with the PostgreSQL output. Any mismatch exits non-zero."""
import io, pathlib, subprocess, sys
import pandas as pd

ROOT = pathlib.Path(__file__).resolve().parent.parent
D = ROOT / "data"


def sql(text):
    r = subprocess.run(["psql", "-X", "-q", "--csv", "-v", "ON_ERROR_STOP=1", "-c", text], capture_output=True, text=True)
    if r.returncode: sys.exit(r.stderr)
    return pd.read_csv(io.StringIO(r.stdout))


def sqlfile(name):
    r = subprocess.run(["psql", "-X", "-q", "--csv", "-v", "ON_ERROR_STOP=1", "-f", str(ROOT / "03_analysis" / name)],
                       capture_output=True, text=True)
    if r.returncode: sys.exit(r.stderr)
    return pd.read_csv(io.StringIO(r.stdout))


o = pd.read_csv(D / "orders.csv"); c = pd.read_csv(D / "customers.csv"); i = pd.read_csv(D / "order_items.csv")
for col in ["order_purchase_timestamp", "order_delivered_customer_date", "order_estimated_delivery_date"]:
    o[col] = pd.to_datetime(o[col])
gmv = i.assign(v=i.price + i.freight_value).groupby("order_id").v.sum().rename("gmv")
d = (o[o.order_status == "delivered"].merge(c, on="customer_id").merge(gmv, on="order_id"))
d["late"] = d.order_delivered_customer_date.dt.normalize() > d.order_estimated_delivery_date
d["dq"] = d.order_delivered_customer_date.isna() | (d.order_delivered_customer_date < d.order_purchase_timestamp)

checks = []
# 1. total delivered revenue and delivered-order count
s = sql("SELECT round(sum(gmv),2) AS rev, count(*) AS n FROM olist.v_customer_orders").iloc[0]
checks.append(("delivered revenue (R$)", round(d.gmv.sum(), 2), float(s.rev)))
checks.append(("delivered orders", len(d), int(s.n)))
# 2. unique customers with a delivered order
checks.append(("customers with a delivered order", d.customer_unique_id.nunique(),
               int(sql("SELECT count(DISTINCT customer_unique_id) n FROM olist.v_customer_orders").n[0])))
# 3. Q8: top-20% revenue share
spend = d.groupby("customer_unique_id").gmv.sum().sort_values(ascending=False)
q8 = sqlfile("q08_revenue_concentration.sql")
checks.append(("Q8 top-20% revenue share (%)", round(100 * spend.iloc[: int(len(spend) * 0.2)].sum() / spend.sum(), 1),
               float(q8.loc[q8.customer_decile <= 2, "pct_of_revenue"].sum().round(1))))
# 4. Q6: repeat rate within 180 days, on time vs late
d = d.sort_values(["customer_unique_id", "order_purchase_timestamp"])
first = d.groupby("customer_unique_id").head(1)
maxts = d.order_purchase_timestamp.max()
elig = first[(first.order_purchase_timestamp <= maxts - pd.Timedelta(days=180)) & ~first.dq]
later = d[["customer_unique_id", "order_purchase_timestamp"]].rename(columns={"order_purchase_timestamp": "t2"})
m = elig.merge(later, on="customer_unique_id")
m = m[(m.t2 > m.order_purchase_timestamp) & (m.t2 <= m.order_purchase_timestamp + pd.Timedelta(days=180))]
rep = set(m.customer_unique_id)
elig = elig.assign(rep=elig.customer_unique_id.isin(rep))
q6 = sqlfile("q06_late_delivery_vs_repeat.sql").set_index("first_delivery")
for lab, flag in (("On time", False), ("Late", True)):
    sub = elig[elig.late == flag]
    checks.append((f"Q6 customers ({lab})", len(sub), int(q6.loc[lab, "customers"])))
    checks.append((f"Q6 repeat rate % ({lab})", round(100 * sub.rep.mean(), 1), float(q6.loc[lab, "repeat_rate_pct"])))
# 5. RFM materialised view matches the Q3 query
q3 = sqlfile("q03_rfm_segmentation.sql").set_index("segment").customers
mv = sql("SELECT segment, count(*) AS customers FROM olist.mv_rfm GROUP BY 1").set_index("segment").customers
checks.append(("RFM: mv_rfm segment sizes == Q3", int((q3.sort_index() == mv.sort_index()).all()), 1))

bad = 0
print(f"{'check':42s}{'pandas':>14s}{'postgres':>14s}  result")
for name, a, b in checks:
    ok = abs(a - b) < 0.011
    bad += not ok
    print(f"{name:42s}{a:>14,}{b:>14,}  {'OK' if ok else 'MISMATCH'}")
sys.exit(1 if bad else 0)
