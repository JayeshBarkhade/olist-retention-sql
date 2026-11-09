# EXPLAIN ANALYZE: before vs after indexing

Median of 7 runs (after 1 warm-up run), all data cached in memory, PostgreSQL 16.15. Full plans are in `results/plans/`.

| Query | Before (ms) | After (ms) | Speed-up | Indexes used after |
|---|---:|---:|---:|---|
| Order history of one customer (join customers -> orders -> items) | 17.1 | 0.2 | 72.6x | idx_customers_unique_id, idx_orders_customer_purchase |
| Daily revenue for one week (date-range filter on delivered orders) | 23.5 | 29.4 | 0.8x | idx_orders_delivered_purchase |
| Units and revenue for ONE product (e.g. a product page) | 11.1 | 0.5 | 21.8x | idx_items_product |
| Q6: late delivery vs repeat purchase (full analytical query) | 677.8 | 883.5 | 0.8x | idx_customers_unique_id, idx_orders_customer_purchase |
| Q10: top 3 products per category (LATERAL) | 532.6 | 493.5 | 1.1x | (none: planner kept seq scan) |

Indexes created: `idx_customers_unique_id`, `idx_orders_customer_purchase`, `idx_orders_delivered_purchase`, `idx_items_product`
