-- Phase 2b: staging -> clean typed tables. Order matters because of foreign keys.
BEGIN;

INSERT INTO olist.product_category_translation
SELECT product_category_name, product_category_name_english FROM staging.product_category_name_translation;

INSERT INTO olist.customers
SELECT customer_id, customer_unique_id, lpad(trim(customer_zip_code_prefix), 5, '0'),
       lower(translate(trim(customer_city), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')),
       upper(trim(customer_state))
FROM staging.customers;

INSERT INTO olist.sellers
SELECT seller_id, lpad(trim(seller_zip_code_prefix), 5, '0'),
       lower(translate(trim(seller_city), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')),
       upper(trim(seller_state))
FROM staging.sellers;

INSERT INTO olist.products
SELECT product_id, NULLIF(trim(product_category_name), ''), product_weight_g::int, product_length_cm::int,
       product_height_cm::int, product_width_cm::int, product_photos_qty::int
FROM staging.products;

-- Orders: cast text -> timestamp, repair impossible timestamps, and leave an audit trail in dq_flag.
INSERT INTO olist.orders
SELECT order_id, customer_id, order_status,
       order_purchase_timestamp::timestamp,
       NULLIF(order_approved_at, '')::timestamp,
       NULLIF(order_delivered_carrier_date, '')::timestamp,
       CASE WHEN NULLIF(order_delivered_customer_date, '')::timestamp >= order_purchase_timestamp::timestamp
            THEN order_delivered_customer_date::timestamp END,
       NULLIF(order_estimated_delivery_date, '')::timestamp::date,
       CASE WHEN NULLIF(order_delivered_customer_date, '')::timestamp < order_purchase_timestamp::timestamp
                 THEN 'delivered_before_purchase'
            WHEN order_status = 'delivered' AND NULLIF(order_delivered_customer_date, '') IS NULL
                 THEN 'delivered_missing_date' END
FROM staging.orders;

INSERT INTO olist.order_items
SELECT order_id, order_item_id::int, product_id, seller_id, NULLIF(shipping_limit_date, '')::timestamp,
       price::numeric, freight_value::numeric
FROM staging.order_items;

INSERT INTO olist.order_payments
SELECT order_id, payment_sequential::int, payment_type, payment_installments::int, payment_value::numeric
FROM staging.order_payments;

-- Reviews: keep exactly one row per order = the most recently answered one.
INSERT INTO olist.order_reviews
SELECT review_id, order_id, review_score::smallint, NULLIF(trim(review_comment_title), ''),
       NULLIF(trim(review_comment_message), ''), NULLIF(review_creation_date, '')::timestamp,
       NULLIF(review_answer_timestamp, '')::timestamp
FROM (SELECT r.*, ROW_NUMBER() OVER (PARTITION BY order_id
                                     ORDER BY review_answer_timestamp DESC, review_id) AS rn
      FROM staging.order_reviews r) ranked
WHERE rn = 1;

COMMIT;
ANALYZE;
