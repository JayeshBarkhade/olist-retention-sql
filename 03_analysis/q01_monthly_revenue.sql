-- Q1. Monthly revenue, order count and month-over-month growth.
-- Skills: DATE_TRUNC, CTE, LAG() window, running total with SUM() OVER.
WITH monthly AS (
  SELECT date_trunc('month', purchase_ts)::date AS month, count(*) AS orders, sum(gmv) AS revenue
  FROM olist.v_customer_orders
  GROUP BY 1)
SELECT month, orders, round(revenue, 0) AS revenue_rs,
       round(100.0 * (revenue - LAG(revenue) OVER w) / NULLIF(LAG(revenue) OVER w, 0), 1) AS mom_growth_pct,
       round(sum(revenue) OVER (ORDER BY month), 0) AS cumulative_revenue_rs
FROM monthly
WINDOW w AS (ORDER BY month)
ORDER BY month;
