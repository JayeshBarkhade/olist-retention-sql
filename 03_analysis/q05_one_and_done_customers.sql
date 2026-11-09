-- Q5. How many customers bought once and NEVER came back (and what was their first order worth)?
-- Skills: DISTINCT ON, NOT EXISTS anti-join (in WHERE, so it becomes a Hash Anti Join), MATERIALIZED CTE.
-- Only customers whose first order is at least 180 days before the end of the data are counted,
-- so recent buyers who simply have not had time to return are not mislabelled as lost.
-- Performance notes (details in README "Lessons learned" and 04_optimization/slow_q05_correlated_view.sql):
--   1. NOT EXISTS sits in WHERE, so it becomes a Hash Anti Join. Inside an aggregate FILTER it can never
--      become a join and runs as a per-row SubPlan.
--   2. The CTE is NOT MATERIALIZED (inlined) so the planner keeps real table statistics for row estimates.
WITH co AS NOT MATERIALIZED (
  SELECT customer_unique_id, purchase_ts, gmv FROM olist.v_customer_orders),
bounds AS (
  SELECT max(purchase_ts) AS max_ts FROM co),
firsts AS (
  SELECT DISTINCT ON (customer_unique_id) customer_unique_id, purchase_ts, gmv
  FROM co ORDER BY customer_unique_id, purchase_ts),
eligible AS (
  SELECT f.* FROM firsts f CROSS JOIN bounds b WHERE f.purchase_ts <= b.max_ts - interval '180 days'),
never_returned AS (
  SELECT e.* FROM eligible e
  WHERE NOT EXISTS (SELECT 1 FROM co o
                    WHERE o.customer_unique_id = e.customer_unique_id AND o.purchase_ts > e.purchase_ts))
SELECT (SELECT count(*) FROM eligible) AS eligible_customers,
       count(*) AS never_returned,
       round(100.0 * count(*) / (SELECT count(*) FROM eligible), 1) AS never_returned_pct,
       round(avg(gmv), 2) AS avg_first_order_of_lost_rs,
       round(sum(gmv), 0) AS total_first_order_value_of_lost_rs
FROM never_returned;
