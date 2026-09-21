-- =============================================================================
-- ETL: staging.product_category_translation -> core.product_category_translation
-- =============================================================================
-- Fixes: 2 categories with no translation row (stage 4, section 2.1) are
-- added manually. An 'unknown' -> 'unknown' row is also added because
-- core.products will assign the value 'unknown' to products whose category
-- was NULL in staging (see 05_products.sql); without this row, the foreign
-- key on core.products.product_category_name would fail to load.
--
-- All staging columns are typed TEXT, so every value is explicitly cast to
-- the target VARCHAR(50) to match core.product_category_translation.
--
-- Must run BEFORE 05_products.sql (products.product_category_name references this
-- table).
-- =============================================================================

INSERT INTO core.product_category_translation (product_category_name, product_category_name_english)
SELECT
    TRIM(product_category_name)::VARCHAR(50)          AS product_category_name,
    TRIM(product_category_name_english)::VARCHAR(50)  AS product_category_name_english
FROM staging.product_category_translation

UNION ALL

-- Manually supplied translations for the 2 categories missing from staging.
VALUES
    ('portateis_cozinha_e_preparadores_de_alimentos'::VARCHAR(50), 'portable_kitchen_food_preparers'::VARCHAR(50)),
    ('pc_gamer'::VARCHAR(50), 'pc_gamer'::VARCHAR(50)),
    ('unknown'::VARCHAR(50), 'unknown'::VARCHAR(50));
