-- Phase 4d: secondary indexes. Each one exists because a measured query needed it (see results/explain_before_after.md).
-- Primary keys already index: orders(order_id), order_items(order_id, order_item_id), order_payments(order_id, ...).
-- Deliberately NOT created: indexes on columns no query filters or joins on (every index slows writes and costs disk).

-- Retention queries identify a PERSON by customer_unique_id, but customer_id (per order) is what orders point to.
CREATE INDEX IF NOT EXISTS idx_customers_unique_id ON olist.customers (customer_unique_id);

-- Foreign-key join orders -> customers, and "all orders of this customer in time order" without a sort.
CREATE INDEX IF NOT EXISTS idx_orders_customer_purchase ON olist.orders (customer_id, purchase_ts);

-- PARTIAL index: nearly every report filters on delivered orders and a date range. Indexing only those rows
-- keeps the index smaller and faster than a full purchase_ts index.
CREATE INDEX IF NOT EXISTS idx_orders_delivered_purchase ON olist.orders (purchase_ts) WHERE order_status = 'delivered';

-- Product-level analysis (top products, per-product revenue) joins order_items on product_id.
CREATE INDEX IF NOT EXISTS idx_items_product ON olist.order_items (product_id);

ANALYZE;
