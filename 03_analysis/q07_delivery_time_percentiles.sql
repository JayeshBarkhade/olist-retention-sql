-- Q7. Delivery time by state: average vs median vs 90th percentile, and the late-delivery rate.
-- Skills: PERCENTILE_CONT() WITHIN GROUP, ROLLUP for an overall row, HAVING, EXTRACT(epoch).
-- Why percentiles: averages hide the long tail that customers actually complain about.
SELECT COALESCE(state, 'ALL STATES') AS state, count(*) AS orders,
       round(avg(days)::numeric, 1) AS avg_days,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY days))::numeric, 1) AS median_days,
       round((percentile_cont(0.9) WITHIN GROUP (ORDER BY days))::numeric, 1) AS p90_days,
       round(100.0 * avg(is_late::int), 1) AS late_pct
FROM (SELECT state, is_late, EXTRACT(epoch FROM delivered_ts - purchase_ts) / 86400.0 AS days
      FROM olist.v_customer_orders WHERE dq_flag IS NULL) t
GROUP BY ROLLUP (state)
HAVING count(*) >= 500
ORDER BY (state IS NULL), p90_days DESC;
