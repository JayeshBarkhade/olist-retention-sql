-- Shared building blocks. "Customer" always means customer_unique_id (the real person).
-- Revenue = items price + freight on DELIVERED orders (what the customer actually paid for).
-- Currency is R$ (Brazilian real) to match the Olist convention.
CREATE OR REPLACE VIEW olist.v_order_value AS
SELECT order_id, count(*) AS n_items, sum(price) AS items_value, sum(freight_value) AS freight_value,
       sum(price + freight_value) AS gmv
FROM olist.order_items GROUP BY order_id;

CREATE OR REPLACE VIEW olist.v_customer_orders AS
SELECT c.customer_unique_id, o.order_id, o.purchase_ts, o.delivered_ts, o.estimated_delivery_date,
       o.dq_flag, c.state, v.gmv,
       (o.delivered_ts::date > o.estimated_delivery_date) AS is_late      -- NULL when delivery date unknown
FROM olist.orders o
JOIN olist.customers c USING (customer_id)
JOIN olist.v_order_value v USING (order_id)
WHERE o.order_status = 'delivered';
