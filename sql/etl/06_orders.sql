-- =============================================================================
-- ETL: staging.orders -> core.orders
-- =============================================================================
-- Fix (stage 4, sections 4.1/4.2/4.3): 1,382 rows have out-of-order shipping
-- timestamps (carrier date before approval, or customer date before carrier
-- date). These rows are NOT deleted or corrected — there is no way to
-- recover the true timestamp, and the rest of the row (customer, items,
-- payment, review) is perfectly usable. Instead, has_inconsistent_timestamps
-- flags them so stage 7 queries can exclude them from stage-to-stage
-- duration calculations with a simple WHERE clause.
--
-- Note: when a timestamp is NULL (order not yet at that stage), the
-- comparison evaluates to NULL/unknown, which CASE treats as non-matching,
-- so the row correctly falls through to FALSE rather than being
-- misclassified.
--
-- order_approved_at / order_delivered_carrier_date / order_delivered_customer_date
-- are inserted as-is (nullable in core, stage 4 section 3.1): they
-- legitimately encode the order lifecycle stage and are not defaulted.
--
-- All staging columns are typed TEXT. Timestamps are cast once in the
-- typed_orders CTE so the comparisons used to compute
-- has_inconsistent_timestamps operate on real TIMESTAMP values rather than
-- on text.
--
-- Must run AFTER 03_customers.sql (FK dependency).
-- =============================================================================

WITH typed_orders AS (
    SELECT
        order_id::CHAR(32)                          AS order_id,
        customer_id::CHAR(32)                       AS customer_id,
        order_status::VARCHAR(20)                   AS order_status,
        order_purchase_timestamp::TIMESTAMP         AS order_purchase_timestamp,
        order_approved_at::TIMESTAMP                AS order_approved_at,
        order_delivered_carrier_date::TIMESTAMP     AS order_delivered_carrier_date,
        order_delivered_customer_date::TIMESTAMP    AS order_delivered_customer_date,
        order_estimated_delivery_date::TIMESTAMP    AS order_estimated_delivery_date
    FROM staging.orders
)
INSERT INTO core.orders (
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    has_inconsistent_timestamps
)
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    CASE
        WHEN order_delivered_carrier_date  < order_approved_at             THEN TRUE
        WHEN order_delivered_customer_date < order_delivered_carrier_date  THEN TRUE
        ELSE FALSE
    END AS has_inconsistent_timestamps
FROM typed_orders;
