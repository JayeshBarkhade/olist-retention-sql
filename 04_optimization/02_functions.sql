-- Phase 4b: reusable SQL functions on top of the materialized view.
CREATE OR REPLACE FUNCTION olist.get_customer_segment(p_customer_unique_id text)
RETURNS text LANGUAGE sql STABLE AS
$$ SELECT segment FROM olist.mv_rfm WHERE customer_unique_id = p_customer_unique_id $$;

CREATE OR REPLACE FUNCTION olist.customer_profile(p_customer_unique_id text)
RETURNS TABLE (orders bigint, total_spend_rs numeric, first_order date, last_order date,
               avg_review numeric, segment text)
LANGUAGE sql STABLE AS
$$ SELECT m.frequency, round(m.monetary, 2), m.first_order, m.last_order,
          (SELECT round(avg(r.review_score), 2)
           FROM olist.order_reviews r
           JOIN olist.orders o USING (order_id)
           JOIN olist.customers c USING (customer_id)
           WHERE c.customer_unique_id = m.customer_unique_id),
          m.segment
   FROM olist.mv_rfm m WHERE m.customer_unique_id = p_customer_unique_id $$;

-- Demo: profile of the highest-spending customer, and the segment lookup on its own.
\echo '-- customer_profile() for the top spender'
SELECT * FROM olist.customer_profile((SELECT customer_unique_id FROM olist.mv_rfm ORDER BY monetary DESC LIMIT 1));
\echo '-- get_customer_segment() for the same customer'
SELECT olist.get_customer_segment((SELECT customer_unique_id FROM olist.mv_rfm ORDER BY monetary DESC LIMIT 1)) AS segment;
\echo '-- sanity: segment sizes from the materialised view (must match Q3)'
SELECT segment, count(*) AS customers FROM olist.mv_rfm GROUP BY 1 ORDER BY 1;
