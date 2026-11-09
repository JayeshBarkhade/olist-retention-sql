-- Q11 (bonus). How long after the first order does a repeat buyer come back? Tells us WHEN to run a win-back campaign.
-- Skills: ROW_NUMBER() and LAG() over the same window, percentile aggregates.
WITH seq AS (
  SELECT customer_unique_id, purchase_ts,
         ROW_NUMBER() OVER w AS order_no,
         LAG(purchase_ts) OVER w AS prev_ts
  FROM olist.v_customer_orders
  WINDOW w AS (PARTITION BY customer_unique_id ORDER BY purchase_ts))
SELECT count(*) AS customers_with_2nd_order,
       round((percentile_cont(0.25) WITHIN GROUP (ORDER BY d))::numeric, 0) AS p25_days,
       round((percentile_cont(0.50) WITHIN GROUP (ORDER BY d))::numeric, 0) AS median_days,
       round((percentile_cont(0.75) WITHIN GROUP (ORDER BY d))::numeric, 0) AS p75_days
FROM (SELECT EXTRACT(epoch FROM purchase_ts - prev_ts) / 86400.0 AS d FROM seq WHERE order_no = 2) x;
