-- =============================================================================
-- Validation of core.* after the ETL run (stage 6 -> stage 7 checkpoint)
-- =============================================================================
-- This script does NOT modify data. It re-checks that the load behaved as
-- expected before core is used for business analyses (stage 7). Each query
-- is a diagnostic: read the result and compare it against the "expected"
-- value stated in the comment, taken from docs/04_data_quality.md. Run with:
--   psql -d olist -f sql/tests/validate_core.sql
-- =============================================================================

-- =========================== 1. ROW COUNT CONSISTENCY =======================
-- These tables are loaded with no filtering and no deduplication, so their
-- row count in core must exactly match staging. Any difference means rows
-- were silently dropped or duplicated by a JOIN or a CAST during the ETL.
SELECT 'customers'      AS table_name, (SELECT COUNT(*) FROM staging.customers)      AS staging_count, (SELECT COUNT(*) FROM core.customers)      AS core_count
UNION ALL
SELECT 'sellers',        (SELECT COUNT(*) FROM staging.sellers),                       (SELECT COUNT(*) FROM core.sellers)
UNION ALL
SELECT 'orders',         (SELECT COUNT(*) FROM staging.orders),                        (SELECT COUNT(*) FROM core.orders)
UNION ALL
SELECT 'order_items',    (SELECT COUNT(*) FROM staging.order_items),                   (SELECT COUNT(*) FROM core.order_items)
UNION ALL
SELECT 'order_payments', (SELECT COUNT(*) FROM staging.order_payments),                (SELECT COUNT(*) FROM core.order_payments)
UNION ALL
SELECT 'order_reviews',  (SELECT COUNT(*) FROM staging.order_reviews),                 (SELECT COUNT(*) FROM core.order_reviews)
UNION ALL
SELECT 'products',       (SELECT COUNT(*) FROM staging.products),                      (SELECT COUNT(*) FROM core.products);

-- product_category_translation is expected to be staging + 3 rows: the 2
-- manually mapped categories and the 'unknown' fallback (stage 4, section 2.1).
SELECT
    (SELECT COUNT(*) FROM staging.product_category_translation) + 3     AS expected_count,
    (SELECT COUNT(*) FROM core.product_category_translation)            AS actual_count;

-- geolocation is expected to be close to the number of DISTINCT zip prefixes
-- in staging (19,015, stage 4 section 1.2), minus any prefix whose only
-- raw point(s) fall outside Brazil's bounding box and were therefore
-- excluded by the ETL (see 02_geolocation.sql) — expect actual_count to be
-- slightly below expected_count, not equal.
SELECT
    (SELECT COUNT(DISTINCT geolocation_zip_code_prefix) FROM staging.geolocation)   AS expected_count_upper_bound,
    (SELECT COUNT(*) FROM core.geolocation)                                         AS actual_count;

-- =========================== 2. REGRESSION AGAINST AUDIT FIGURES ============
-- Confirms the ETL fixed exactly what the audit found — not more, not less.
-- A mismatch here means either the audit numbers or the ETL logic changed
-- since docs/04_data_quality.md was written.

-- Expected 610 products with product_category_name = 'unknown' (stage 4, section 3.3).
SELECT COUNT(*) AS products_defaulted_to_unknown
FROM core.products
WHERE product_category_name = 'unknown';

-- Expected 1,382 orders flagged for out-of-order shipping timestamps
-- (1,359 + 23, stage 4 sections 4.1/4.2).
SELECT COUNT(*) AS orders_flagged_inconsistent
FROM core.orders
WHERE has_inconsistent_timestamps = TRUE;

-- Expected 0 rows: the 2 credit_card rows with 0 installments (stage 4,
-- section 4.6) must all have been corrected to 1 by GREATEST().
SELECT COUNT(*) AS remaining_zero_installments
FROM core.order_payments
WHERE payment_installments < 1;

-- =========================== 3. TRANSFORMATION SANITY CHECKS ================
-- Coordinates must fall within Brazil's approximate bounding box. Expected
-- 0 rows: the geolocation ETL now filters out-of-bounds raw points before
-- aggregating (see 02_geolocation.sql); a non-zero result here would mean
-- either that filter regressed or that averaging valid points still landed
-- outside the box, both worth investigating.
SELECT COUNT(*) AS out_of_bounds_coordinates
FROM core.geolocation
WHERE geolocation_lat NOT BETWEEN -34 AND 6
   OR geolocation_lng NOT BETWEEN -74 AND -32;

-- Informational: how many zip prefixes had no valid coordinate at all
-- (all their raw points were outside Brazil) and therefore have no row in
-- core.geolocation. Expected to be small (up to 10, stage 4 addendum).
SELECT COUNT(DISTINCT s.geolocation_zip_code_prefix::INTEGER) AS prefixes_dropped_entirely
FROM staging.geolocation s
LEFT JOIN core.geolocation g
  ON g.geolocation_zip_code_prefix = s.geolocation_zip_code_prefix::INTEGER
WHERE g.geolocation_zip_code_prefix IS NULL;

-- CHAR(n) casts truncate silently instead of raising an error if a value is
-- longer than n. This checks that no id was cut short during the ETL: every
-- id should still be exactly 32 characters after loading.
SELECT 'customers.customer_id' AS column_checked, COUNT(*) AS wrong_length_rows
FROM core.customers WHERE LENGTH(TRIM(customer_id)) <> 32
UNION ALL
SELECT 'orders.order_id', COUNT(*) FROM core.orders WHERE LENGTH(TRIM(order_id)) <> 32
UNION ALL
SELECT 'products.product_id', COUNT(*) FROM core.products WHERE LENGTH(TRIM(product_id)) <> 32
UNION ALL
SELECT 'sellers.seller_id', COUNT(*) FROM core.sellers WHERE LENGTH(TRIM(seller_id)) <> 32
UNION ALL
SELECT 'order_reviews.review_id', COUNT(*) FROM core.order_reviews WHERE LENGTH(TRIM(review_id)) <> 32;

-- The 2 manually mapped translations and the 'unknown' fallback must be
-- present, otherwise the products ETL would have failed on the FK — this
-- confirms they loaded with the exact expected spelling.
SELECT product_category_name, product_category_name_english
FROM core.product_category_translation
WHERE product_category_name IN ('pc_gamer', 'portateis_cozinha_e_preparadores_de_alimentos', 'unknown');

-- =========================== 4. CROSS-TABLE CONSISTENCY ======================
-- Every order should be reachable from order_items through the foreign key;
-- this join-based count acts as an end-to-end sanity check that the whole
-- chain (orders -> order_items -> products -> sellers) is walkable and
-- returns a plausible row count close to staging's order_items count.
SELECT COUNT(*) AS joined_order_items
FROM core.order_items oi
JOIN core.orders o   ON o.order_id = oi.order_id
JOIN core.products p ON p.product_id = oi.product_id
JOIN core.sellers s  ON s.seller_id = oi.seller_id;

-- Revenue computed from order_items should be strictly positive and of a
-- plausible order of magnitude (a basic smoke test, not a precise target).
SELECT
    ROUND(SUM(price + freight_value), 2) AS total_revenue,
    COUNT(*)                             AS total_items
FROM core.order_items;
