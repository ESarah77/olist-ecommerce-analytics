-- =============================================================================
-- ETL: staging.order_items -> core.order_items
-- =============================================================================
-- No content issue found in staging for this table: 0 duplicated
-- (order_id, order_item_id), 0 referential orphan toward orders/products/
-- sellers, 0 rows with price <= 0 or freight_value < 0 (stage 4). This is a
-- direct load; the CHECK constraints in core act as a safety net rather
-- than a correction.
--
-- All staging columns are typed TEXT, so every value is explicitly cast to
-- the type expected by core.order_items (NUMERIC(10,2) for money fields,
-- TIMESTAMP for the shipping deadline).
--
-- Must run AFTER 06_orders.sql, 05_products.sql and 04_sellers.sql
-- (FK dependencies).
-- =============================================================================

INSERT INTO core.order_items (
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
)
SELECT
    order_id::CHAR(32)                    AS order_id,
    order_item_id::SMALLINT               AS order_item_id,
    product_id::CHAR(32)                  AS product_id,
    seller_id::CHAR(32)                   AS seller_id,
    shipping_limit_date::TIMESTAMP        AS shipping_limit_date,
    price::NUMERIC(10, 2)                 AS price,
    freight_value::NUMERIC(10, 2)         AS freight_value
FROM staging.order_items;
