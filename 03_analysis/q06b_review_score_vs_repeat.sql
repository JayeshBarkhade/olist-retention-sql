-- Q6b. Same design as Q6, split by the review score the customer gave their FIRST order.
-- Skills: joins to a second fact table, bucketing with CASE, EXISTS rewritten as a LEFT JOIN.
WITH co AS NOT MATERIALIZED (
  SELECT customer_unique_id, order_id, purchase_ts, dq_flag FROM olist.v_customer_orders),
bounds AS (
  SELECT max(purchase_ts) AS max_ts FROM co),
first_orders AS (
  SELECT DISTINCT ON (customer_unique_id) customer_unique_id, order_id, purchase_ts, dq_flag
  FROM co ORDER BY customer_unique_id, purchase_ts),
eligible AS (
  SELECT f.* FROM first_orders f CROSS JOIN bounds b
  WHERE f.purchase_ts <= b.max_ts - interval '180 days' AND f.dq_flag IS NULL),
repeaters AS (
  SELECT DISTINCT e.customer_unique_id
  FROM eligible e
  JOIN co o ON o.customer_unique_id = e.customer_unique_id
           AND o.purchase_ts > e.purchase_ts
           AND o.purchase_ts <= e.purchase_ts + interval '180 days'),
scored AS (
  SELECT e.*, r.review_score, (rp.customer_unique_id IS NOT NULL) AS repeated_180d
  FROM eligible e
  JOIN olist.order_reviews r USING (order_id)
  LEFT JOIN repeaters rp USING (customer_unique_id))
SELECT CASE WHEN review_score <= 2 THEN '1-2 stars' WHEN review_score = 3 THEN '3 stars' ELSE '4-5 stars' END AS first_order_review,
       count(*) AS customers,
       round(100.0 * count(*) FILTER (WHERE repeated_180d) / count(*), 1) AS repeat_rate_pct
FROM scored GROUP BY 1 ORDER BY 1;
