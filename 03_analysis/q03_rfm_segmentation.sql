-- Q3. RFM segmentation (Recency, Frequency, Monetary) and the revenue each segment holds.
-- Skills: NTILE(), CASE, scalar subquery, window share-of-total.
-- Determinism: recency is whole days, so thousands of customers tie. NTILE splits ties in whatever order rows
-- happen to arrive, which can differ between query plans. Every NTILE therefore ends with customer_unique_id as a
-- tie-breaker (found by the pandas cross-check in tests/, where mv_rfm and this query disagreed without it).
-- Judgement call: ~85% of customers have frequency = 1, so NTILE on frequency would split ties
-- arbitrarily. Frequency is bucketed with CASE instead; Recency and Monetary use NTILE(5).
WITH snapshot AS (
  SELECT max(purchase_ts)::date + 1 AS snap FROM olist.v_customer_orders),
cust AS (
  SELECT customer_unique_id, (SELECT snap FROM snapshot) - max(purchase_ts)::date AS recency_days,
         count(*) AS frequency, sum(gmv) AS monetary
  FROM olist.v_customer_orders GROUP BY 1),
scored AS (
  SELECT *, 6 - NTILE(5) OVER (ORDER BY recency_days, customer_unique_id) AS r_score,       -- 5 = bought most recently
         CASE WHEN frequency >= 3 THEN 3 WHEN frequency = 2 THEN 2 ELSE 1 END AS f_score,
         NTILE(5) OVER (ORDER BY monetary, customer_unique_id) AS m_score                    -- 5 = biggest spender
  FROM cust),
labelled AS (
  SELECT *, CASE
      WHEN f_score >= 2 AND r_score >= 4 THEN '1 Champions (repeat, recent)'
      WHEN f_score >= 2 AND r_score >= 2 THEN '2 Loyal (repeat)'
      WHEN f_score >= 2                  THEN '3 At-risk repeat buyers'
      WHEN r_score >= 4 AND m_score >= 4 THEN '4 New high-value'
      WHEN r_score >= 4                  THEN '5 New'
      WHEN m_score >= 4                  THEN '6 Lapsed high-value (win-back target)'
      ELSE                                    '7 Lapsed low-value' END AS segment
  FROM scored)
SELECT segment, count(*) AS customers,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_customers,
       round(avg(monetary), 0) AS avg_spend_rs,
       round(100.0 * sum(monetary) / sum(sum(monetary)) OVER (), 1) AS pct_revenue
FROM labelled GROUP BY segment ORDER BY segment;
