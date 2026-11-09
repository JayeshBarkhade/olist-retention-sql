-- SLOW VERSION kept on purpose (NOT run by run_all.sh). See README "Lessons learned".
-- Two separate problems made this query unusable, found by reading EXPLAIN:
--  (1) NOT EXISTS probes olist.v_customer_orders, a view that joins 3 tables and contains a GROUP BY.
--      PostgreSQL cannot flatten that into a hash anti-join, so EXPLAIN shows a "SubPlan" containing the whole
--      Hash Join over order_items, re-executed once per customer.
--  (2) The EXISTS sits inside an aggregate FILTER (WHERE ...). A sub-select there can never be pulled up into a
--      join, so it stays a per-row SubPlan even after the data is flattened into a CTE (tested: still >2 minutes).
--  (3) Even with a join instead of EXISTS, a MATERIALIZED CTE has no statistics: DISTINCT ON over it is
--      estimated at 200 rows, the filters shrink that to 1 row, and the planner picks a Nested Loop that
--      re-runs a sort+unique subplan ~43K times (tested on the Q6 pattern: >2 minutes).
-- Measured on ~98K orders: version (1) was still running after 5 minutes and was cancelled.
-- Fix: move NOT EXISTS into WHERE (-> Hash Anti Join) and keep the CTE NOT MATERIALIZED so base-table
-- statistics survive. Final Q5/Q6/Q6b run in well under a second. See 03_analysis/q05 and README.
WITH bounds AS (
  SELECT max(purchase_ts) AS max_ts FROM olist.v_customer_orders),
firsts AS (
  SELECT DISTINCT ON (customer_unique_id) customer_unique_id, purchase_ts, gmv
  FROM olist.v_customer_orders ORDER BY customer_unique_id, purchase_ts),
eligible AS (
  SELECT f.* FROM firsts f CROSS JOIN bounds b WHERE f.purchase_ts <= b.max_ts - interval '180 days')
SELECT count(*) AS eligible_customers,
       count(*) FILTER (WHERE NOT EXISTS (
            SELECT 1 FROM olist.v_customer_orders o
            WHERE o.customer_unique_id = e.customer_unique_id AND o.purchase_ts > e.purchase_ts)) AS never_returned,
       round(100.0 * count(*) FILTER (WHERE NOT EXISTS (
            SELECT 1 FROM olist.v_customer_orders o
            WHERE o.customer_unique_id = e.customer_unique_id AND o.purchase_ts > e.purchase_ts)) / count(*), 1) AS never_returned_pct,
       round(avg(gmv), 2) AS avg_first_order_rs
FROM eligible e;
