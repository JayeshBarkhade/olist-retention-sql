-- Q8. Revenue concentration (Pareto): what share of revenue comes from the top 10% / 20% of customers?
-- Skills: NTILE(), nested window over aggregate, cumulative percentage.
WITH cust AS (
  SELECT customer_unique_id, sum(gmv) AS spend FROM olist.v_customer_orders GROUP BY 1),
bucketed AS (
  SELECT spend, NTILE(10) OVER (ORDER BY spend DESC) AS decile FROM cust)
SELECT decile AS customer_decile, count(*) AS customers, round(sum(spend), 0) AS revenue_rs,
       round(100.0 * sum(spend) / sum(sum(spend)) OVER (), 1) AS pct_of_revenue,
       round(100.0 * sum(sum(spend)) OVER (ORDER BY decile) / sum(sum(spend)) OVER (), 1) AS cumulative_pct
FROM bucketed GROUP BY decile ORDER BY decile;
