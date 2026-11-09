-- Phase 1b: bulk load with \copy (client-side COPY, so it works without server file access).
-- Run from the project root so the relative data/ paths resolve.
\copy staging.customers FROM 'data/customers.csv' WITH (FORMAT csv, HEADER true)
\copy staging.orders FROM 'data/orders.csv' WITH (FORMAT csv, HEADER true)
\copy staging.order_items FROM 'data/order_items.csv' WITH (FORMAT csv, HEADER true)
\copy staging.order_payments FROM 'data/order_payments.csv' WITH (FORMAT csv, HEADER true)
\copy staging.order_reviews FROM 'data/order_reviews.csv' WITH (FORMAT csv, HEADER true)
\copy staging.products FROM 'data/products.csv' WITH (FORMAT csv, HEADER true)
\copy staging.sellers FROM 'data/sellers.csv' WITH (FORMAT csv, HEADER true)
\copy staging.product_category_name_translation FROM 'data/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true)
