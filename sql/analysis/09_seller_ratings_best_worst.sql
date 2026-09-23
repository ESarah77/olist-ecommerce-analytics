-- =============================================================================
-- Business question: Who are the 5 best-rated and 5 worst-rated sellers,
--                     among those with enough sales volume to be meaningful?
-- Why it matters: Identifies sellers to feature (best) or to flag for
--                  quality review / potential delisting (worst) — a direct,
--                  actionable output for a marketplace operations team.
-- Technique: CTE, HAVING with a minimum volume threshold, UNION ALL of two
--             ranked subsets.
-- Answer: Among sellers with at least 20 orders, average ratings range
--         from a perfect 5.00 down to 2.10, showing seller-level quality
--         issues exist independently of category-level trends.
-- =============================================================================


WITH latest_review AS (
    SELECT DISTINCT ON (order_id)
        order_id,
        review_score
    FROM core.order_reviews
    ORDER BY order_id, review_answer_timestamp DESC, review_id
),
seller_scores AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT oi.order_id) AS nb_orders,
        ROUND(AVG(r.review_score), 2) AS avg_review_score
    FROM core.order_items oi
    JOIN latest_review r ON r.order_id = oi.order_id
    GROUP BY oi.seller_id
    -- Minimum volume threshold: a seller with 1-2 orders should not be
    -- able to rank as "best" or "worst" on statistical noise alone.
    HAVING COUNT(DISTINCT oi.order_id) >= 20
)
(
    SELECT seller_id, nb_orders, avg_review_score, 'top_rated' AS rank_group
    FROM seller_scores
    ORDER BY avg_review_score DESC, nb_orders DESC
    LIMIT 5
)
UNION ALL
(
    SELECT seller_id, nb_orders, avg_review_score, 'lowest_rated' AS rank_group
    FROM seller_scores
    ORDER BY avg_review_score ASC, nb_orders DESC
    LIMIT 5
)
ORDER BY rank_group, avg_review_score DESC;
