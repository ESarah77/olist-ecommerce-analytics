-- =============================================================================
-- ETL: staging.customers -> core.customers
-- =============================================================================
-- No content issue found in staging for this table (0 NULLs, 0 duplicates,
-- 0 referential issue toward orders, stage 4). Text fields are trimmed and
-- the state code is uppercased as cheap insurance against inconsistent
-- casing/whitespace, even though none was detected during exploration.
--
-- No FK to core.geolocation: 157 zip prefixes have no geolocation match
-- (stage 4, section 2.2). Geolocation is joined as an enrichment at query
-- time in stage 7, not stored redundantly here.
--
-- All staging columns are typed TEXT, so every value is explicitly cast to
-- the type expected by core.customers (CHAR(32) for ids, INTEGER for the
-- zip prefix).
-- =============================================================================

INSERT INTO core.customers (
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
)
SELECT
    customer_id::CHAR(32)                       AS customer_id,
    customer_unique_id::CHAR(32)                AS customer_unique_id,
    customer_zip_code_prefix::INTEGER           AS customer_zip_code_prefix,
    TRIM(customer_city)::VARCHAR(60)            AS customer_city,
    UPPER(TRIM(customer_state))::CHAR(2)        AS customer_state
FROM staging.customers;
