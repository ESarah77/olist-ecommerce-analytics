-- =============================================================================
-- ML feature view: predicting customer dissatisfaction (review_score <= 3)
-- =============================================================================
-- Business problem: predict, from order and delivery characteristics known
-- by the time a customer could plausibly leave a review, whether that
-- customer will be dissatisfied (review_score <= 3) or satisfied (>= 4).
-- This directly extends stage 7 / query 02: late delivery is strongly
-- associated with low review scores (2.57 vs 4.29 average score).
--
-- Data leakage precautions:
--   - No column derived from the review itself is used as a feature: only
--     review_score is read, and only to build the target label.
--     review_comment_title, review_comment_message, review_creation_date
--     and review_answer_timestamp never appear as a feature.
--   - Scope is restricted to 'delivered' orders with a known delivery date
--     (same rule as core.orders / stage 4, section 4.4): training on
--     canceled or in-transit orders would use information that does not
--     exist yet at prediction time.
--   - No seller- or customer-level historical rating aggregate is used
--     (e.g. "this seller's average past score"). Computing that correctly
--     requires a point-in-time cutoff per order to avoid leaking the
--     target order's own review into its own feature — real complexity
--     for a component that is intentionally kept secondary in this project.
--   - The "most recent review per order" deduplication rule from stage 6 is
--     reapplied here rather than assumed: core.order_reviews deliberately
--     keeps the full, undeduplicated grain (stage 4, section 1.1).
--
-- One row per delivered, reviewed order.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS ml;

CREATE OR REPLACE VIEW ml.dissatisfaction_features AS
WITH latest_review AS (
    SELECT DISTINCT ON (order_id)
        order_id,
        review_score
    FROM core.order_reviews
    ORDER BY order_id, review_answer_timestamp DESC, review_id
),
order_items_agg AS (
    SELECT
        oi.order_id,
        COUNT(*)                          AS nb_items,
        COUNT(DISTINCT oi.seller_id)      AS nb_distinct_sellers,
        COUNT(DISTINCT oi.product_id)     AS nb_distinct_products,
        SUM(oi.price)                     AS total_price,
        SUM(oi.freight_value)             AS total_freight,
        AVG(p.product_weight_g)           AS avg_product_weight_g
    FROM core.order_items oi
    JOIN core.products p ON p.product_id = oi.product_id
    GROUP BY oi.order_id
),
primary_item AS (
    -- Simplification: the item with the lowest order_item_id stands in for
    -- the order's category, rather than trying to reconcile several
    -- categories within one multi-item basket. Documented limitation, not
    -- a leakage risk.
    SELECT DISTINCT ON (oi.order_id)
        oi.order_id,
        COALESCE(t.product_category_name_english, p.product_category_name) AS primary_category
    FROM core.order_items oi
    JOIN core.products p ON p.product_id = oi.product_id
    LEFT JOIN core.product_category_translation t ON t.product_category_name = p.product_category_name
    ORDER BY oi.order_id, oi.order_item_id
),
payment_agg AS (
    SELECT
        order_id,
        SUM(payment_value)                                     AS total_payment_value,
        MAX(payment_installments)                              AS max_installments,
        -- Simplification: the payment_type of the first payment_sequential
        -- represents the order (most orders have a single payment line).
        (ARRAY_AGG(payment_type ORDER BY payment_sequential))[1] AS payment_type
    FROM core.order_payments
    GROUP BY order_id
)
SELECT
    o.order_id,

    -- ---- Target ----
    CASE WHEN r.review_score <= 3 THEN 1 ELSE 0 END AS is_dissatisfied,

    -- ---- Order value & composition ----
    oia.nb_items,
    oia.nb_distinct_sellers,
    oia.nb_distinct_products,
    oia.total_price,
    oia.total_freight,
    ROUND(oia.total_freight / NULLIF(oia.total_price, 0), 4) AS freight_ratio,
    oia.avg_product_weight_g,
    pi.primary_category,

    -- ---- Payment ----
    pa.payment_type,
    pa.max_installments,
    pa.total_payment_value,

    -- ---- Delivery timing (the central hypothesis, stage 7 query 02) ----
    (o.order_estimated_delivery_date::date - o.order_purchase_timestamp::date)  AS estimated_delivery_days,
    (o.order_delivered_customer_date::date - o.order_purchase_timestamp::date) AS actual_delivery_days,
    (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS delivery_delay_days,
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
         THEN 1 ELSE 0 END AS is_late,

    -- ---- Purchase context ----
    EXTRACT(DOW FROM o.order_purchase_timestamp)::INT   AS purchase_weekday,
    EXTRACT(MONTH FROM o.order_purchase_timestamp)::INT AS purchase_month,
    c.customer_state

FROM core.orders o
JOIN latest_review r     ON r.order_id = o.order_id
JOIN core.customers c    ON c.customer_id = o.customer_id
JOIN order_items_agg oia ON oia.order_id = o.order_id
JOIN primary_item pi     ON pi.order_id = o.order_id
JOIN payment_agg pa      ON pa.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;
