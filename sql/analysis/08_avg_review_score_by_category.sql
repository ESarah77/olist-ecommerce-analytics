-- =============================================================================
-- Business question: How does average customer satisfaction vary across
--                     product categories?
-- Why it matters: Flags categories with a structural satisfaction problem
--                  (product quality, description accuracy, packaging) that
--                  a purely revenue-based view (query 06) would miss.
-- Technique: CTE, DISTINCT ON for deduplication, LEFT JOIN, HAVING.
-- Answer: Average scores range from 3.49 (office_furniture) to 4.45
--         (books_general_interest) across 63 qualifying categories — a
--         much narrower spread than the revenue concentration seen in
--         query 06, showing commercial success and satisfaction are not
--         driven by the same categories.
-- =============================================================================


WITH latest_review AS (
    -- Same deduplication rule as query 02: keep the most recent review
    -- per order.
    SELECT DISTINCT ON (order_id)
        order_id,
        review_score
    FROM core.order_reviews
    ORDER BY order_id, review_answer_timestamp DESC, review_id
)
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name) AS category,
    COUNT(DISTINCT oi.order_id) AS nb_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM core.order_items oi
JOIN core.products p ON p.product_id = oi.product_id
LEFT JOIN core.product_category_translation t ON t.product_category_name = p.product_category_name
JOIN latest_review r ON r.order_id = oi.order_id
GROUP BY 1
-- Minimum volume threshold: a category with 2 orders and 1 bad review
-- would otherwise look like the worst-rated category in the catalogue.
HAVING COUNT(DISTINCT oi.order_id) >= 30
ORDER BY avg_review_score ASC;
