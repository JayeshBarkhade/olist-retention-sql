-- Q10. Top 3 products by revenue inside each of the 6 biggest categories.
-- Skills: CROSS JOIN LATERAL (a per-row "top-N" subquery), LIMIT inside a subquery, joins to a lookup table.
-- LATERAL lets the inner query reference the outer row (c.category_name), which a plain join cannot.
WITH big_cats AS (
  SELECT p.category_name, sum(i.price) AS revenue
  FROM olist.order_items i JOIN olist.products p USING (product_id)
  JOIN olist.orders o USING (order_id)
  WHERE o.order_status = 'delivered' AND p.category_name IS NOT NULL
  GROUP BY 1 ORDER BY 2 DESC LIMIT 6)
SELECT t.category_name_english AS category, row_number() OVER (PARTITION BY c.category_name ORDER BY top.revenue DESC) AS rank_in_category,
       left(top.product_id, 8) AS product, top.units, round(top.revenue, 0) AS revenue_rs
FROM big_cats c
JOIN olist.product_category_translation t ON t.category_name = c.category_name
CROSS JOIN LATERAL (
  SELECT i.product_id, count(*) AS units, sum(i.price) AS revenue
  FROM olist.order_items i
  JOIN olist.products p USING (product_id)
  JOIN olist.orders o USING (order_id)
  WHERE p.category_name = c.category_name AND o.order_status = 'delivered'
  GROUP BY i.product_id ORDER BY revenue DESC LIMIT 3) top
ORDER BY c.revenue DESC, rank_in_category;
