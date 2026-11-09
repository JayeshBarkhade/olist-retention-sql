-- Phase 2c: POST-LOAD VALIDATION. Every check should show problems = 0 (row counts are informational).
SELECT 'row count: ' || t AS check_name, n AS problems FROM (
  SELECT 'customers' t, count(*) n FROM olist.customers UNION ALL
  SELECT 'orders', count(*) FROM olist.orders UNION ALL
  SELECT 'order_items', count(*) FROM olist.order_items UNION ALL
  SELECT 'order_payments', count(*) FROM olist.order_payments UNION ALL
  SELECT 'order_reviews', count(*) FROM olist.order_reviews UNION ALL
  SELECT 'products', count(*) FROM olist.products UNION ALL
  SELECT 'sellers', count(*) FROM olist.sellers) c
UNION ALL SELECT 'orders without a customer (orphans)', count(*) FROM olist.orders o
  WHERE NOT EXISTS (SELECT 1 FROM olist.customers c WHERE c.customer_id = o.customer_id)
UNION ALL SELECT 'items without a product (orphans)', count(*) FROM olist.order_items i
  WHERE NOT EXISTS (SELECT 1 FROM olist.products p WHERE p.product_id = i.product_id)
UNION ALL SELECT 'delivered_ts before purchase_ts', count(*) FROM olist.orders WHERE delivered_ts < purchase_ts
UNION ALL SELECT 'orders with more than one review',
  count(*) FROM (SELECT order_id FROM olist.order_reviews GROUP BY order_id HAVING count(*) > 1) x
UNION ALL SELECT 'rows repaired and flagged in orders (informational)', count(*) FROM olist.orders WHERE dq_flag IS NOT NULL
UNION ALL SELECT 'payment total <> items total (delivered orders)', count(*) FROM (
  SELECT o.order_id FROM olist.orders o
  JOIN (SELECT order_id, sum(price + freight_value) v FROM olist.order_items GROUP BY 1) i USING (order_id)
  JOIN (SELECT order_id, sum(payment_value) p FROM olist.order_payments GROUP BY 1) p USING (order_id)
  WHERE o.order_status = 'delivered' AND abs(i.v - p.p) > 0.01) z;
