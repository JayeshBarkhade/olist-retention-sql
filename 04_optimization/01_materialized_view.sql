-- Phase 4a: MATERIALIZED VIEW for RFM.
-- Why: RFM scores need a full scan + two window sorts over every customer. Dashboards and the
-- get_customer_segment() function should read a precomputed table, not recompute it on every call.
-- Trade-off: the data is a snapshot; refresh it after each data load (REFRESH ... CONCURRENTLY keeps it readable).
DROP MATERIALIZED VIEW IF EXISTS olist.mv_rfm CASCADE;
CREATE MATERIALIZED VIEW olist.mv_rfm AS
WITH snapshot AS (
  SELECT max(purchase_ts)::date + 1 AS snap FROM olist.v_customer_orders),
cust AS (
  SELECT customer_unique_id, (SELECT snap FROM snapshot) - max(purchase_ts)::date AS recency_days,
         count(*) AS frequency, sum(gmv) AS monetary, min(purchase_ts)::date AS first_order, max(purchase_ts)::date AS last_order
  FROM olist.v_customer_orders GROUP BY 1),
scored AS (
  SELECT *, 6 - NTILE(5) OVER (ORDER BY recency_days, customer_unique_id) AS r_score,
         CASE WHEN frequency >= 3 THEN 3 WHEN frequency = 2 THEN 2 ELSE 1 END AS f_score,
         NTILE(5) OVER (ORDER BY monetary, customer_unique_id) AS m_score
  FROM cust)
SELECT customer_unique_id, recency_days, frequency, monetary, first_order, last_order, r_score, f_score, m_score,
       CASE
         WHEN f_score >= 2 AND r_score >= 4 THEN '1 Champions (repeat, recent)'
         WHEN f_score >= 2 AND r_score >= 2 THEN '2 Loyal (repeat)'
         WHEN f_score >= 2                  THEN '3 At-risk repeat buyers'
         WHEN r_score >= 4 AND m_score >= 4 THEN '4 New high-value'
         WHEN r_score >= 4                  THEN '5 New'
         WHEN m_score >= 4                  THEN '6 Lapsed high-value (win-back target)'
         ELSE                                    '7 Lapsed low-value' END AS segment
FROM scored;

-- A UNIQUE index is required for REFRESH ... CONCURRENTLY and also makes single-customer lookups instant.
CREATE UNIQUE INDEX mv_rfm_customer_uidx ON olist.mv_rfm (customer_unique_id);
CREATE INDEX mv_rfm_segment_idx ON olist.mv_rfm (segment);
REFRESH MATERIALIZED VIEW CONCURRENTLY olist.mv_rfm;
ANALYZE olist.mv_rfm;
