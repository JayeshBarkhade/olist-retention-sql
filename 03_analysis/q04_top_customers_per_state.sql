-- Q4. Top 3 customers by spend within each of the 5 highest-revenue states.
-- Skills: DENSE_RANK() OVER (PARTITION BY ...), subquery in WHERE, grouping.
WITH spend AS (
  SELECT state, customer_unique_id, count(*) AS orders, sum(gmv) AS spend
  FROM olist.v_customer_orders GROUP BY 1, 2),
top_states AS (
  SELECT state FROM spend GROUP BY state ORDER BY sum(spend) DESC LIMIT 5),
ranked AS (
  SELECT *, DENSE_RANK() OVER (PARTITION BY state ORDER BY spend DESC) AS rnk
  FROM spend WHERE state IN (SELECT state FROM top_states))
SELECT state, rnk AS rank_in_state, left(customer_unique_id, 8) AS customer, orders, round(spend, 2) AS spend_rs
FROM ranked WHERE rnk <= 3 ORDER BY state, rnk;
