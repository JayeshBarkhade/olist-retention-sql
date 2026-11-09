-- Phase 1c: CLEAN, typed, normalized schema with constraints.
-- Design notes
--  * customer_id is per ORDER in Olist; customer_unique_id identifies the real person. Retention
--    analysis MUST count customer_unique_id, otherwise every customer looks like a one-time buyer.
--  * Constraints encode business rules (no delivery before purchase, no negative prices, one review
--    per order). The cleaning step exists so that these constraints can be enforced.
--  * Secondary indexes are deliberately NOT created here. They are added in 04_optimization with
--    measured before/after timings, so each index is justified by evidence.
DROP SCHEMA IF EXISTS olist CASCADE;
CREATE SCHEMA olist;

CREATE TABLE olist.product_category_translation (
    category_name         text PRIMARY KEY,
    category_name_english text NOT NULL
);

CREATE TABLE olist.customers (
    customer_id        char(32) PRIMARY KEY,
    customer_unique_id char(32) NOT NULL,
    zip_code_prefix    char(5),
    city               text,
    state              char(2) NOT NULL
);

CREATE TABLE olist.sellers (
    seller_id       char(32) PRIMARY KEY,
    zip_code_prefix char(5),
    city            text,
    state           char(2) NOT NULL
);

CREATE TABLE olist.products (
    product_id    char(32) PRIMARY KEY,
    category_name text REFERENCES olist.product_category_translation (category_name),  -- NULL = unknown
    weight_g      integer CHECK (weight_g >= 0),
    length_cm     integer CHECK (length_cm > 0),
    height_cm     integer CHECK (height_cm > 0),
    width_cm      integer CHECK (width_cm > 0),
    photos_qty    integer CHECK (photos_qty >= 0)
);

CREATE TABLE olist.orders (
    order_id                char(32) PRIMARY KEY,
    customer_id             char(32) NOT NULL REFERENCES olist.customers (customer_id),
    order_status            text NOT NULL CHECK (order_status IN
        ('created','approved','invoiced','processing','shipped','delivered','canceled','unavailable')),
    purchase_ts             timestamp NOT NULL,
    approved_ts             timestamp,
    carrier_ts              timestamp,
    delivered_ts            timestamp,
    estimated_delivery_date date,
    dq_flag                 text,   -- set by the cleaning step when a source value was repaired
    CONSTRAINT delivered_after_purchase CHECK (delivered_ts IS NULL OR delivered_ts >= purchase_ts)
);

CREATE TABLE olist.order_items (
    order_id            char(32) NOT NULL REFERENCES olist.orders (order_id),
    order_item_id       integer  NOT NULL,
    product_id          char(32) NOT NULL REFERENCES olist.products (product_id),
    seller_id           char(32) NOT NULL REFERENCES olist.sellers (seller_id),
    shipping_limit_date timestamp,
    price               numeric(10,2) NOT NULL CHECK (price >= 0),
    freight_value       numeric(10,2) NOT NULL CHECK (freight_value >= 0),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE olist.order_payments (
    order_id             char(32) NOT NULL REFERENCES olist.orders (order_id),
    payment_sequential   integer  NOT NULL,
    payment_type         text     NOT NULL,
    payment_installments integer  NOT NULL CHECK (payment_installments >= 1),
    payment_value        numeric(10,2) NOT NULL CHECK (payment_value >= 0),
    PRIMARY KEY (order_id, payment_sequential)
);

CREATE TABLE olist.order_reviews (
    review_id              char(32) PRIMARY KEY,
    order_id               char(32) NOT NULL UNIQUE REFERENCES olist.orders (order_id),  -- one review per order after dedupe
    review_score           smallint NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    comment_title          text,
    comment_message        text,
    review_created_ts      timestamp,
    review_answered_ts     timestamp
);
