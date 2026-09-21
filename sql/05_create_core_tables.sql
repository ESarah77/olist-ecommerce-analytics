-- =============================================================================
-- STAGE 5 — CORE SCHEMA
-- =============================================================================
-- This script declares the structural rules that every row of the "core"
-- schema must satisfy: types, primary keys, foreign keys, NOT NULL, CHECK.
-- It does NOT load or transform any data — that happens in stage 6 (ETL),
-- see sql/etl/*.sql. Decisions below are justified in docs/04_data_quality.md.
--
-- Renamed columns fix typos or clarify meaning found in the raw staging
-- tables (e.g. "lenght" -> "length", "geolocation_zip_code_prefix" ->
-- "zip_code_prefix" once the table is scoped by its own name).
--
-- Run with:
--   psql -d olist -f sql/05_create_core_tables.sql
-- =============================================================================

DROP SCHEMA IF EXISTS core CASCADE;
CREATE SCHEMA core;

-- -----------------------------------------------------------------------------
-- product_category_translation
-- -----------------------------------------------------------------------------
-- No data quality issue on this table itself (PK verified unique in stage 4).
-- The ETL (stage 6) extends this table with two manually-provided translations
-- ('pc_gamer', 'portateis_cozinha_e_preparadores_de_alimentos') and one
-- 'unknown' -> 'unknown' row, so that every category referenced by
-- core.products — including the ones defaulted to 'unknown' — resolves
-- through the foreign key below.
-- -----------------------------------------------------------------------------
CREATE TABLE core.product_category_translation (
    product_category_name           VARCHAR(50) NOT NULL,
    product_category_name_english   VARCHAR(50) NOT NULL,
    CONSTRAINT pk_product_category_translation PRIMARY KEY (product_category_name)
);

-- -----------------------------------------------------------------------------
-- geolocation
-- -----------------------------------------------------------------------------
-- Rebuilt by the ETL as one row per zip prefix (stage 4, section 5.1):
-- staging had no primary key (1,000,163 rows / 19,015 distinct prefixes,
-- 128,174 duplicated groups). city/state are resolved by mode, lat/lng by
-- averaging the distinct points only (duplicates removed first).
-- -----------------------------------------------------------------------------
CREATE TABLE core.geolocation (
    geolocation_zip_code_prefix     INTEGER         NOT NULL,
    geolocation_lat                 NUMERIC(10, 7)  NOT NULL,
    geolocation_lng                 NUMERIC(10, 7)  NOT NULL,
    geolocation_city                VARCHAR(60)     NOT NULL,
    geolocation_state               CHAR(2)         NOT NULL,
    CONSTRAINT pk_geolocation PRIMARY KEY (geolocation_zip_code_prefix)
);

-- -----------------------------------------------------------------------------
-- customers
-- -----------------------------------------------------------------------------
-- No FK to geolocation: geolocation is an enrichment lookup, not a parent
-- entity. 157 customer zip prefixes have no geolocation match (stage 4,
-- section 2.2) — a blocking FK would force deleting valid customers because
-- of missing reference data. Coordinates are joined as NULL where absent.
-- -----------------------------------------------------------------------------
CREATE TABLE core.customers (
    customer_id             CHAR(32)     NOT NULL,
    customer_unique_id      CHAR(32)     NOT NULL,
    customer_zip_code_prefix INTEGER     NOT NULL,
    customer_city           VARCHAR(60)  NOT NULL,
    customer_state          CHAR(2)      NOT NULL,
    CONSTRAINT pk_customers PRIMARY KEY (customer_id)
);

-- -----------------------------------------------------------------------------
-- sellers
-- -----------------------------------------------------------------------------
-- Same reasoning as customers: no FK to geolocation (7 orphan prefixes,
-- stage 4, section 2.2).
-- -----------------------------------------------------------------------------
CREATE TABLE core.sellers (
    seller_id               CHAR(32)     NOT NULL,
    seller_zip_code_prefix  INTEGER      NOT NULL,
    seller_city             VARCHAR(60)  NOT NULL,
    seller_state            CHAR(2)      NOT NULL,
    CONSTRAINT pk_sellers PRIMARY KEY (seller_id)
);

-- -----------------------------------------------------------------------------
-- products
-- -----------------------------------------------------------------------------
-- Renamed: product_name_lenght -> product_name_length,
--          product_description_lenght -> product_description_length
--          (typo fix, stage 4 exploration notes).
-- category_name is NOT NULL: the ETL replaces the 610 raw NULLs with
-- 'unknown' (stage 4, section 3.3) so that no product is silently dropped
-- from category-level reporting. It references the translation table, which
-- the ETL extends with an 'unknown' row to keep the FK valid.
-- The 6 measurement columns (weight/dimensions, 2 raw NULLs) and the 3
-- catalogue-metadata columns (name/description length, photo count, 610 raw
-- NULLs) stay nullable: they are measurements, not dimensions, and are never
-- imputed (stage 4, section 3.3).
-- -----------------------------------------------------------------------------
CREATE TABLE core.products (
    product_id                          CHAR(32)     NOT NULL,
    product_category_name               VARCHAR(50)  NOT NULL,
    product_name_length                 SMALLINT,
    product_description_length          INTEGER,
    product_photos_qty                  SMALLINT,
    product_weight_g                    INTEGER,
    product_length_cm                   INTEGER,
    product_height_cm                   INTEGER,
    product_width_cm                    INTEGER,
    CONSTRAINT pk_products PRIMARY KEY (product_id),
    CONSTRAINT fk_products_category
        FOREIGN KEY (product_category_name)
        REFERENCES core.product_category_translation (product_category_name),
    CONSTRAINT chk_products_weight_positive
        CHECK (product_weight_g IS NULL OR product_weight_g >= 0),
    CONSTRAINT chk_products_dimensions_positive
        CHECK (
            (product_length_cm IS NULL OR product_length_cm > 0) AND
            (product_height_cm IS NULL OR product_height_cm > 0) AND
            (product_width_cm  IS NULL OR product_width_cm  > 0)
        )
);

-- -----------------------------------------------------------------------------
-- orders
-- -----------------------------------------------------------------------------
-- order_approved_at / order_delivered_carrier_date / order_delivered_customer_date
-- stay nullable: they legitimately encode the order lifecycle stage
-- (stage 4, section 3.1) — a NOT NULL constraint would reject ~3% of valid
-- orders that simply have not reached that stage.
-- order_status is constrained to the 8 values observed during exploration.
-- has_inconsistent_timestamps is an ETL-computed flag (stage 4, section 4.3)
-- for the 1,382 rows where carrier/customer delivery timestamps are out of
-- order; rows are kept, not deleted, and this column lets downstream queries
-- exclude them from stage-to-stage duration calculations.
-- -----------------------------------------------------------------------------
CREATE TABLE core.orders (
    order_id                        CHAR(32)    NOT NULL,
    customer_id                     CHAR(32)    NOT NULL,
    order_status                    VARCHAR(20) NOT NULL,
    order_purchase_timestamp        TIMESTAMP   NOT NULL,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   TIMESTAMP   NOT NULL,
    has_inconsistent_timestamps     BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_orders PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id)
        REFERENCES core.customers (customer_id),
    CONSTRAINT chk_orders_status
        CHECK (order_status IN (
            'created', 'approved', 'processing', 'invoiced',
            'shipped', 'delivered', 'unavailable', 'canceled'
        )),
    CONSTRAINT chk_orders_approved_after_purchase
        CHECK (order_approved_at IS NULL OR order_approved_at >= order_purchase_timestamp)
);

-- -----------------------------------------------------------------------------
-- order_items
-- -----------------------------------------------------------------------------
-- price > 0 and freight_value >= 0 enforced: stage 4, section 4 confirmed
-- 0 violations in staging, so the constraint documents an already-true
-- invariant rather than requiring a correction.
-- -----------------------------------------------------------------------------
CREATE TABLE core.order_items (
    order_id             CHAR(32)       NOT NULL,
    order_item_id        SMALLINT       NOT NULL,
    product_id           CHAR(32)       NOT NULL,
    seller_id            CHAR(32)       NOT NULL,
    shipping_limit_date  TIMESTAMP      NOT NULL,
    price                NUMERIC(10, 2) NOT NULL,
    freight_value        NUMERIC(10, 2) NOT NULL,
    CONSTRAINT pk_order_items PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT fk_order_items_order
        FOREIGN KEY (order_id)
        REFERENCES core.orders (order_id),
    CONSTRAINT fk_order_items_product
        FOREIGN KEY (product_id)
        REFERENCES core.products (product_id),
    CONSTRAINT fk_order_items_seller
        FOREIGN KEY (seller_id)
        REFERENCES core.sellers (seller_id),
    CONSTRAINT chk_order_items_price_positive
        CHECK (price > 0),
    CONSTRAINT chk_order_items_freight_non_negative
        CHECK (freight_value >= 0)
);

-- -----------------------------------------------------------------------------
-- order_payments
-- -----------------------------------------------------------------------------
-- payment_value >= 0 (not > 0): stage 4, section 4.5 found 9 legitimate
-- zero-value lines on 'not_defined' / 'voucher' payment types — a stricter
-- ">0" constraint would reject valid rows.
-- payment_installments >= 1: stage 4, section 4.6 found 2 credit_card rows
-- at 0, corrected to 1 by the ETL (GREATEST(payment_installments, 1)).
-- payment_type is constrained to the 5 values observed during exploration.
-- -----------------------------------------------------------------------------
CREATE TABLE core.order_payments (
    order_id             CHAR(32)       NOT NULL,
    payment_sequential   SMALLINT       NOT NULL,
    payment_type         VARCHAR(20)    NOT NULL,
    payment_installments SMALLINT       NOT NULL,
    payment_value        NUMERIC(10, 2) NOT NULL,
    CONSTRAINT pk_order_payments PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT fk_order_payments_order
        FOREIGN KEY (order_id)
        REFERENCES core.orders (order_id),
    CONSTRAINT chk_order_payments_type
        CHECK (payment_type IN (
            'credit_card', 'boleto', 'voucher', 'debit_card', 'not_defined'
        )),
    CONSTRAINT chk_order_payments_installments_min
        CHECK (payment_installments >= 1),
    CONSTRAINT chk_order_payments_value_non_negative
        CHECK (payment_value >= 0)
);

-- -----------------------------------------------------------------------------
-- order_reviews
-- -----------------------------------------------------------------------------
-- Composite PK (review_id, order_id): stage 4, section 1.1 showed neither
-- column is unique alone (814 duplicated review_id, 551 duplicated order_id)
-- because the survey allows multiple answers per order and one answer can be
-- attached to several orders. The grain is preserved here; deduplication to
-- "one score per order" (most recent review) happens only in the analytical
-- / ML layer (stage 7/8), never in core.
-- review_comment_title / _message stay nullable (88% / 59% NULL, legitimate
-- optional free text, stage 4 section 3.2).
-- -----------------------------------------------------------------------------
CREATE TABLE core.order_reviews (
    review_id               CHAR(32)    NOT NULL,
    order_id                CHAR(32)    NOT NULL,
    review_score            SMALLINT    NOT NULL,
    review_comment_title    VARCHAR(100),
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP   NOT NULL,
    review_answer_timestamp TIMESTAMP   NOT NULL,
    CONSTRAINT pk_order_reviews PRIMARY KEY (review_id, order_id),
    CONSTRAINT fk_order_reviews_order
        FOREIGN KEY (order_id)
        REFERENCES core.orders (order_id),
    CONSTRAINT chk_order_reviews_score_range
        CHECK (review_score BETWEEN 1 AND 5),
    CONSTRAINT chk_order_reviews_answer_after_creation
        CHECK (review_answer_timestamp >= review_creation_date)
);

-- -----------------------------------------------------------------------------
-- Indexes on foreign keys (not auto-created by PostgreSQL, needed for join
-- performance in stage 7 analytical queries).
-- -----------------------------------------------------------------------------
CREATE INDEX idx_orders_customer_id        ON core.orders (customer_id);
CREATE INDEX idx_order_items_product_id    ON core.order_items (product_id);
CREATE INDEX idx_order_items_seller_id     ON core.order_items (seller_id);
CREATE INDEX idx_order_payments_order_id   ON core.order_payments (order_id);
CREATE INDEX idx_order_reviews_order_id    ON core.order_reviews (order_id);
CREATE INDEX idx_products_category_name    ON core.products (product_category_name);
