-- =============================================================================
-- Business question: Which 10 product categories generate the most revenue,
--                     and what share of total revenue do they represent?
-- Why it matters: Identifies where the catalogue and marketing effort should
--                  concentrate, and how revenue-concentrated the business
--                  is across categories.
-- Technique: CTE, LEFT JOIN for optional translation, SUM() OVER() window
--             function for both a percentage-of-total and a cumulative share.
-- Answer: The top 10 categories account for 62.3% of total revenue, led
--         by health_beauty (9.1%), watches_gifts (8.3%) and bed_bath_table
--         (7.9%) — no single category dominates the catalogue.
-- =============================================================================


WITH category_revenue AS (
    SELECT
        -- product_category_name_english is NULL only if a category slipped through
        -- without a translation, which should not happen after the ETL
        -- (stage 6) — COALESCE is a defensive fallback, not an expected path.
        COALESCE(t.product_category_name_english, p.product_category_name) AS category,
        SUM(oi.price + oi.freight_value) AS revenue
    FROM core.order_items oi
    JOIN core.products p ON p.product_id = oi.product_id
    LEFT JOIN core.product_category_translation t ON t.product_category_name = p.product_category_name
    JOIN core.orders o ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1
)
SELECT
    category,
    ROUND(revenue, 2) AS revenue,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 2) AS pct_of_total_revenue,
    ROUND(
        100.0 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 2
    ) AS cumulative_pct_of_total_revenue
FROM category_revenue
ORDER BY revenue DESC
LIMIT 10;
