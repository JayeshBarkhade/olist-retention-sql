-- Q9. Which product categories have months with ZERO sales (a gap an aggregate GROUP BY never shows)?
-- Skills: generate_series, CROSS JOIN to build a full calendar grid, LEFT JOIN, FILTER, COALESCE.
-- A plain GROUP BY only returns months that HAVE rows; the calendar grid is what exposes the gaps.
WITH months AS (
  SELECT generate_series(date_trunc('month', min(purchase_ts)), date_trunc('month', max(purchase_ts)),
                         interval '1 month')::date AS m
  FROM olist.orders WHERE order_status = 'delivered'),
cats AS (
  SELECT DISTINCT COALESCE(p.category_name, 'unknown') AS category FROM olist.products p),
sales AS (
  SELECT COALESCE(p.category_name, 'unknown') AS category, date_trunc('month', o.purchase_ts)::date AS m,
         sum(i.price) AS revenue
  FROM olist.order_items i
  JOIN olist.orders o USING (order_id)
  JOIN olist.products p USING (product_id)
  WHERE o.order_status = 'delivered'
  GROUP BY 1, 2)
SELECT c.category, count(*) FILTER (WHERE s.revenue IS NULL) AS months_with_zero_sales,
       count(*) AS months_in_range,
       round(100.0 * count(*) FILTER (WHERE s.revenue IS NULL) / count(*), 0) AS pct_months_zero
FROM cats c CROSS JOIN months mo
LEFT JOIN sales s ON s.category = c.category AND s.m = mo.m
GROUP BY c.category
HAVING count(*) FILTER (WHERE s.revenue IS NULL) > 0
ORDER BY months_with_zero_sales DESC, c.category
LIMIT 12;
