-- =============================================================================
-- Reporting view for the Power BI dashboard: one row per order
-- =============================================================================
-- Purpose: expose order-level KPIs and scope flags with the SAME business rules
-- as the SQL analyses in sql/analysis/, so that Power BI figures can be
-- reconciled with the SQL reference results.
--
-- Rules reused from the analysis stage:
--   - Revenue scope: orders that are not 'canceled' or 'unavailable'.
--   - Delivery KPIs: 'delivered' orders with a known delivery date only.
--   - One review per order: the most recent one (core.order_reviews keeps the
--     full grain, see docs/04_data_quality.md, section 1.1).
--   - Customers are identified by customer_unique_id (customer_id is unique
--     per order in Olist, so joining core.customers adds no duplicate rows).
--
-- Flags are stored as 1/0 so that DAX can SUM them directly.
-- Run with:  psql -d olist -f sql/reporting/orders_enriched.sql
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS reporting;

CREATE OR REPLACE VIEW reporting.orders_enriched AS
WITH latest_review AS (
    -- One review per order: the most recent answer
    SELECT DISTINCT ON (order_id) order_id, review_score
    FROM core.order_reviews
    ORDER BY order_id, review_answer_timestamp DESC, review_id
),
base AS (
    SELECT
        o.*,
        (o.order_status = 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL) AS delivered
    FROM core.orders o
)
SELECT
    b.order_id,
    b.customer_id,
    b.order_status,
    b.order_purchase_timestamp::date AS order_purchase_date,

    -- Scope flags (1/0 so that DAX can simply SUM them)
    CASE WHEN b.order_status NOT IN ('canceled', 'unavailable') THEN 1 ELSE 0 END AS is_revenue_order,
    CASE WHEN b.delivered THEN 1 ELSE 0 END AS is_delivered,
    CASE WHEN b.delivered
          AND b.order_delivered_customer_date > b.order_estimated_delivery_date
         THEN 1 ELSE 0 END AS is_late,

    -- Delivery metrics: defined for delivered orders only, NULL otherwise
    CASE WHEN b.delivered
         THEN b.order_delivered_customer_date::date - b.order_purchase_timestamp::date
    END AS delivery_days,
    CASE WHEN b.delivered
         THEN b.order_estimated_delivery_date::date - b.order_purchase_timestamp::date
    END AS estimated_delivery_days,

    r.review_score,

    -- Customer attributes (customer_id is unique per order: no duplication)
    c.customer_unique_id,
    c.customer_state
FROM base b
LEFT JOIN latest_review r ON r.order_id = b.order_id
JOIN core.customers c ON c.customer_id = b.customer_id;
