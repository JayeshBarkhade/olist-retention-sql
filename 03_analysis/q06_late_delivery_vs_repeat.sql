-- Q6. Does a LATE FIRST DELIVERY reduce the chance a customer orders again within 180 days?
-- Skills: DISTINCT ON, EXISTS rewritten as a LEFT JOIN, FILTER, CASE, full-observation-window cohort design.
-- Design choices: (1) first delivered order per person; (2) only people with 180 observable days;
-- (3) rows with repaired/unknown delivery dates (dq_flag) are excluded.
-- Caveat: this shows association, not proof of causation (late deliveries cluster in remote states).
-- Performance: "repeaters" is a plain join (hash join), not a per-row EXISTS subplan (see README).
WITH co AS NOT MATERIALIZED (
  SELECT customer_unique_id, purchase_ts, is_late, dq_flag FROM olist.v_customer_orders),
bounds AS (
  SELECT max(purchase_ts) AS max_ts FROM co),
first_orders AS (
  SELECT DISTINCT ON (customer_unique_id) customer_unique_id, purchase_ts, is_late, dq_flag
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
flagged AS (
  SELECT e.*, (r.customer_unique_id IS NOT NULL) AS repeated_180d
  FROM eligible e LEFT JOIN repeaters r USING (customer_unique_id))
SELECT CASE WHEN is_late THEN 'Late' ELSE 'On time' END AS first_delivery,
       count(*) AS customers,
       count(*) FILTER (WHERE repeated_180d) AS repeat_buyers,
       round(100.0 * count(*) FILTER (WHERE repeated_180d) / count(*), 1) AS repeat_rate_pct
FROM flagged GROUP BY is_late ORDER BY is_late;
