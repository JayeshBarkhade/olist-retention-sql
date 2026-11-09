-- Q12 (bonus, MBA angle). Break-even and ROI of a win-back voucher aimed at the "Lapsed high-value" RFM segment.
-- Skills: reuse of the RFM logic, parameter CTE, VALUES scenario table, derived break-even maths.
-- !! ALL four parameters below are ASSUMPTIONS made up for illustration, not facts from the data.
--    Replace them with the real margin / voucher / messaging cost before presenting numbers.
WITH params AS (
  SELECT 0.25::numeric AS contribution_margin,   -- assumed share of order value kept as profit
         10.00::numeric AS voucher_rs,            -- assumed voucher value, paid only if redeemed
         0.40::numeric AS contact_cost_rs),       -- assumed cost to message one customer
snapshot AS (SELECT max(purchase_ts)::date + 1 AS snap FROM olist.v_customer_orders),
cust AS (
  SELECT customer_unique_id, (SELECT snap FROM snapshot) - max(purchase_ts)::date AS recency_days,
         count(*) AS frequency, sum(gmv) AS monetary, avg(gmv) AS aov
  FROM olist.v_customer_orders GROUP BY 1),
scored AS (
  SELECT *, 6 - NTILE(5) OVER (ORDER BY recency_days, customer_unique_id) AS r_score, NTILE(5) OVER (ORDER BY monetary, customer_unique_id) AS m_score FROM cust),
target AS (
  SELECT count(*) AS n, avg(aov) AS aov FROM scored WHERE frequency = 1 AND r_score <= 3 AND m_score >= 4),
scen AS (SELECT * FROM (VALUES (0.02), (0.05), (0.08)) v(reactivation_rate))
SELECT t.n AS target_customers, round(t.aov, 2) AS avg_order_value_rs, s.reactivation_rate,
       round(t.n * s.reactivation_rate) AS expected_reactivated,
       round(t.n * p.contact_cost_rs, 0) AS campaign_cost_contact_rs,
       round(t.n * s.reactivation_rate * p.voucher_rs, 0) AS voucher_cost_rs,
       round(t.n * s.reactivation_rate * t.aov * p.contribution_margin, 0) AS profit_before_costs_rs,
       round(t.n * s.reactivation_rate * (t.aov * p.contribution_margin - p.voucher_rs) - t.n * p.contact_cost_rs, 0) AS net_profit_rs,
       round(p.contact_cost_rs / (t.aov * p.contribution_margin - p.voucher_rs) * 100, 2) AS break_even_rate_pct
FROM target t CROSS JOIN params p CROSS JOIN scen s ORDER BY s.reactivation_rate;
