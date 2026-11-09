-- Phase 2a: DATA-QUALITY REPORT on the raw staging data (run BEFORE cleaning).
-- Each row = one issue, how many rows it touches, and how it is handled in 02_transform.sql.
SELECT issue, affected_rows, handling FROM (
  SELECT 1 AS n, 'Duplicate review rows (same review_id appears twice)' AS issue,
         (SELECT count(*) - count(DISTINCT review_id) FROM staging.order_reviews) AS affected_rows,
         'Kept one row per order (latest answer timestamp) via ROW_NUMBER()' AS handling
  UNION ALL SELECT 2, 'Orders with more than one distinct review_id',
         (SELECT count(*) FROM (SELECT order_id FROM staging.order_reviews GROUP BY order_id
                                HAVING count(DISTINCT review_id) > 1) x),
         'Kept the most recent review only'
  UNION ALL SELECT 3, 'Delivered timestamp earlier than purchase timestamp',
         (SELECT count(*) FROM staging.orders
          WHERE NULLIF(order_delivered_customer_date,'')::timestamp < order_purchase_timestamp::timestamp),
         'delivered_ts set to NULL, row kept, dq_flag = delivered_before_purchase'
  UNION ALL SELECT 4, 'Status = delivered but delivery date missing',
         (SELECT count(*) FROM staging.orders
          WHERE order_status = 'delivered' AND NULLIF(order_delivered_customer_date,'') IS NULL),
         'Row kept, dq_flag = delivered_missing_date; excluded from delivery-time analysis'
  UNION ALL SELECT 5, 'Orders with no order_items rows',
         (SELECT count(*) FROM staging.orders o
          WHERE NOT EXISTS (SELECT 1 FROM staging.order_items i WHERE i.order_id = o.order_id)),
         'Kept (cancelled/unavailable orders); excluded from revenue by joining to items'
  UNION ALL SELECT 6, 'City names needing normalisation (case, spaces, accents)',
         (SELECT count(*) FROM staging.customers
          WHERE customer_city <> lower(translate(trim(customer_city),
                'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc'))),
         'lower(translate(trim(city))) in the transform'
  UNION ALL SELECT 7, 'Products with missing category',
         (SELECT count(*) FROM staging.products WHERE NULLIF(product_category_name,'') IS NULL),
         'category_name left NULL; reported as "unknown" in analysis'
  UNION ALL SELECT 8, 'Customers rows vs real people (customer_id is per ORDER)',
         (SELECT count(*) - count(DISTINCT customer_unique_id) FROM staging.customers),
         'Not an error: analysis must group by customer_unique_id'
) q ORDER BY n;
