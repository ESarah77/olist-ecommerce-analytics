-- =============================================================================
-- ETL: staging.olist_geolocation_dataset -> core.geolocation
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
--
-- Fix (found via sql/tests/validate_core.sql, documented as an addendum to
-- stage 4): 10 raw points fall clearly outside Brazil's bounding box
-- (e.g. longitude 121.1, latitude 28.0) — data entry / geocoding errors in
-- the source CSV. The true
-- coordinate cannot be recovered, so these points are excluded from the
-- aggregation rather than left to distort the average. A zip prefix backed
-- only by such a point simply gets no row in core.geolocation, which
-- enrichment joins already treat as "no coordinates available" — the same
-- outcome as the 157/7 prefixes with no geolocation match at all
-- (stage 4, section 2.2).
-- =============================================================================

WITH distinct_points AS (
    -- Step 1: cast, discard points outside Brazil's bounding box, then
    -- remove exact duplicate rows before any aggregation.
    SELECT DISTINCT
        geolocation_zip_code_prefix::INTEGER       AS geolocation_zip_code_prefix,
        geolocation_lat::NUMERIC(10, 7)             AS geolocation_lat,
        geolocation_lng::NUMERIC(10, 7)             AS geolocation_lng,
        TRIM(geolocation_city)::VARCHAR(60)         AS geolocation_city,
        UPPER(TRIM(geolocation_state))::CHAR(2)     AS geolocation_state
    FROM staging.geolocation
    WHERE geolocation_lat::NUMERIC(10, 7) BETWEEN -34 AND 6
      AND geolocation_lng::NUMERIC(10, 7) BETWEEN -74 AND -32
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
