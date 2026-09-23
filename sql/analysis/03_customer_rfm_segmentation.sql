-- =============================================================================
-- Business question: How can customers be segmented by Recency, Frequency
--                     and Monetary value to prioritize marketing effort?
-- Why it matters: RFM turns a flat customer list into actionable groups
--                  (e.g. "recent big spenders" vs "one-time buyers"),
--                  which is the standard first step before any retention
--                  or targeting campaign.
-- Technique: multiple CTEs, NTILE() window function, CROSS JOIN, CASE.
-- Answer: Among ~93,000 customers with a delivered order, segments split
--         roughly evenly: champions (~23.6k), at_risk (~22.8k),
--         new_or_occasional (~22.8k) and others (~24.2k).
-- Caveat: with only ~3% of customers making a repeat purchase (see query 04),
--         the Frequency dimension has limited discriminative power here —
--         most customers cluster at frequency = 1. Worth stating explicitly
--         rather than presenting RFM as equally powerful on all 3 axes.
-- =============================================================================


WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        SUM(oi.price + oi.freight_value) AS order_value
    FROM core.orders o
    JOIN core.customers c    ON c.customer_id = o.customer_id
    JOIN core.order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, o.order_id, o.order_purchase_timestamp
),
rfm_base AS (
    SELECT
        customer_unique_id,
        MAX(order_purchase_timestamp) AS last_purchase,
        COUNT(DISTINCT order_id)      AS frequency,
        SUM(order_value)              AS monetary
    FROM customer_orders
    GROUP BY customer_unique_id
),
reference_date AS (
    -- Reference point for recency: one day after the last purchase in the
    -- whole dataset, so recency_days is always >= 1.
    SELECT MAX(order_purchase_timestamp) + INTERVAL '1 day' AS ref_date
    FROM customer_orders
),
rfm_scored AS (
    SELECT
        b.customer_unique_id,
        EXTRACT(DAY FROM (r.ref_date - b.last_purchase))::INT AS recency_days,
        b.frequency,
        b.monetary,
        -- Ordering by recency_days DESC puts the least recent customers in
        -- bucket 1 and the most recent in bucket 4, so a higher score always
        -- means "better" across all three dimensions.
        NTILE(4) OVER (ORDER BY EXTRACT(DAY FROM (r.ref_date - b.last_purchase)) DESC) AS recency_score,
        NTILE(4) OVER (ORDER BY b.frequency ASC)  AS frequency_score,
        NTILE(4) OVER (ORDER BY b.monetary ASC)   AS monetary_score
    FROM rfm_base b
    CROSS JOIN reference_date r
)
SELECT
    recency_score,
    frequency_score,
    monetary_score,
    COUNT(*) AS nb_customers,
    CASE
        WHEN recency_score >= 3 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'champions'
        WHEN recency_score <= 2 AND frequency_score >= 3                        THEN 'at_risk'
        WHEN recency_score >= 3 AND frequency_score <= 2                        THEN 'new_or_occasional'
        ELSE 'others'
    END AS segment
FROM rfm_scored
GROUP BY recency_score, frequency_score, monetary_score
ORDER BY recency_score DESC, frequency_score DESC, monetary_score DESC;
