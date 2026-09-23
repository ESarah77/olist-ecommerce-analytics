-- =============================================================================
-- Business question: Do orders delivered late receive worse review scores
--                     than orders delivered on time?
-- Why it matters: If late delivery drives dissatisfaction, logistics
--                  reliability becomes a direct lever on customer satisfaction
--                  and retention, not just an operational metric. This
--                  finding also motivates the ML feature set in stage 8.
-- Technique: CTE, DISTINCT ON for deduplication, CASE, FILTER clause.
-- Answer: Late orders average a 2.57 review score versus 4.29 for on-time
--         orders, and 65.4% of late orders receive a dissatisfied score
--         (<=3) versus 17.2% for on-time orders.
-- =============================================================================


WITH latest_review AS (
    -- One order can have several review answers (stage 4, section 1.1);
    -- only the most recent one is kept as the customer's final opinion.
    SELECT DISTINCT ON (order_id)
        order_id,
        review_score
    FROM core.order_reviews
    ORDER BY order_id, review_answer_timestamp DESC, review_id
),
delivered AS (
    SELECT
        order_id,
        CASE
            WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'late'
            ELSE 'on_time'
        END AS delivery_status
    FROM core.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
)
SELECT
    d.delivery_status,
    COUNT(*) AS nb_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.review_score <= 3) / COUNT(*), 1) AS pct_dissatisfied
FROM delivered d
JOIN latest_review r ON r.order_id = d.order_id
GROUP BY d.delivery_status
ORDER BY d.delivery_status;
