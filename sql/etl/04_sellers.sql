-- =============================================================================
-- ETL: staging.sellers -> core.sellers
-- =============================================================================
-- Same reasoning as customers (03_customers.sql): no content issue found
-- (stage 4), light text normalization only, no FK to core.geolocation
-- (7 orphan zip prefixes, stage 4 section 2.2).
--
-- All staging columns are typed TEXT, so every value is explicitly cast to
-- the type expected by core.sellers (CHAR(32) for the id, INTEGER for the
-- zip prefix).
-- =============================================================================

INSERT INTO core.sellers (
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
)
SELECT
    seller_id::CHAR(32)                     AS seller_id,
    seller_zip_code_prefix::INTEGER         AS seller_zip_code_prefix,
    TRIM(seller_city)::VARCHAR(60)          AS seller_city,
    UPPER(TRIM(seller_state))::CHAR(2)      AS seller_state
FROM staging.sellers;
