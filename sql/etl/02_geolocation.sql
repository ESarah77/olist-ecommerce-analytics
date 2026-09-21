-- =============================================================================
-- ETL: staging.geolocation -> core.geolocation
-- =============================================================================
-- Fixes (stage 4, section 5.1):
--   1. 128,174 exact duplicate rows in staging: removed with DISTINCT before
--      any aggregation, otherwise a repeated point would be over-weighted
--      in the average below (technical artefact of the CSV export, not a
--      geographic reality). Casting happens before DISTINCT so that two
--      textually different but numerically equal values (e.g. "1.0" vs
--      "1.00") are correctly treated as duplicates.
--   2. 93.5% of zip prefixes have several distinct coordinate pairs: staging
--      has no usable primary key. core.geolocation is rebuilt as one row per
--      zip prefix: lat/lng are averaged over the distinct points, and
--      city/state are resolved by mode (most frequent spelling), not by an
--      arbitrary MIN()/MAX().
--
-- All staging columns are typed TEXT, so every value is explicitly cast to
-- the type expected by core.geolocation (INTEGER for the zip prefix,
-- NUMERIC(10,7) for coordinates).
-- =============================================================================

WITH distinct_points AS (
    -- Step 1: cast then remove exact duplicate rows before any aggregation.
    SELECT DISTINCT
        geolocation_zip_code_prefix::INTEGER       AS geolocation_zip_code_prefix,
        geolocation_lat::NUMERIC(10, 7)             AS geolocation_lat,
        geolocation_lng::NUMERIC(10, 7)             AS geolocation_lng,
        TRIM(geolocation_city)::VARCHAR(60)         AS geolocation_city,
        UPPER(TRIM(geolocation_state))::CHAR(2)     AS geolocation_state
    FROM staging.geolocation
),
city_mode AS (
    -- Step 2: for each zip prefix, rank (city, state) pairs by frequency
    -- among the distinct points, to pick the most common spelling.
    SELECT
        geolocation_zip_code_prefix,
        geolocation_city,
        geolocation_state,
        ROW_NUMBER() OVER (
            PARTITION BY geolocation_zip_code_prefix
            ORDER BY COUNT(*) DESC, geolocation_city
        ) AS row_nb
    FROM distinct_points
    GROUP BY geolocation_zip_code_prefix, geolocation_city, geolocation_state
),
centroid AS (
    -- Step 3: average coordinates over the distinct points only.
    SELECT
        geolocation_zip_code_prefix,
        AVG(geolocation_lat) AS geolocation_lat,
        AVG(geolocation_lng) AS geolocation_lng
    FROM distinct_points
    GROUP BY geolocation_zip_code_prefix
)
INSERT INTO core.geolocation (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state)
SELECT
    c.geolocation_zip_code_prefix,
    c.geolocation_lat,
    c.geolocation_lng,
    m.geolocation_city,
    m.geolocation_state
FROM centroid c
JOIN city_mode m
  ON m.geolocation_zip_code_prefix = c.geolocation_zip_code_prefix
 AND m.row_nb = 1;
