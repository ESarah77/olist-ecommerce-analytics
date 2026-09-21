-- =============================================================================
-- ETL: staging.products -> core.products
-- =============================================================================
-- Fixes (stage 4, section 3.3):
--   - product_category_name: 610 NULLs replaced by 'unknown', so these
--     products stay visible in category-level reporting instead of being
--     silently dropped by GROUP BY. Requires 'unknown' to already exist in
--     core.product_category_translation (01_product_category_translation.sql
--     must run first).
--   - The 6 measurement columns (weight/dimensions) and the 3 catalogue
--     metadata columns (name/description length, photo count) are left
--     NULL when missing: they are measurements, not dimensions, and are
--     never imputed with a fabricated value.
--
-- Source columns keep the staging spelling (product_name_lenght,
-- product_description_lenght): the typo lives in the staging table itself.
-- It is corrected only in the output alias, matching the fixed name
-- declared in core.products (product_name_length, product_description_length).
--
-- All staging columns are typed TEXT, so every value is explicitly cast to
-- the type expected by core.products.
--
-- Must run AFTER 01_product_category_translation.sql (FK dependency).
-- =============================================================================

INSERT INTO core.products (
    product_id,
    product_category_name,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)
SELECT
    product_id::CHAR(32)                                                       AS product_id,
    COALESCE(NULLIF(TRIM(product_category_name), ''), 'unknown')::VARCHAR(50)  AS product_category_name,
    product_name_lenght::SMALLINT           AS product_name_length,
    product_description_lenght::INTEGER     AS product_description_length,
    product_photos_qty::SMALLINT            AS product_photos_qty,
    product_weight_g::INTEGER               AS product_weight_g,
    product_length_cm::INTEGER              AS product_length_cm,
    product_height_cm::INTEGER              AS product_height_cm,
    product_width_cm::INTEGER               AS product_width_cm
FROM staging.products;
