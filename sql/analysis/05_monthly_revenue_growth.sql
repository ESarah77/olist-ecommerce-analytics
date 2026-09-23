
-- =============================================================================
-- Business question: How has monthly revenue evolved, and what is the
--                     month-over-month growth rate?
-- Why it matters: The most basic health check of an e-commerce business —
--                  spotting seasonality, plateaus or decline early is a
--                  precondition for any other commercial decision.
-- Technique: CTE, DATE_TRUNC, LAG() window function.
-- Answer: Revenue grew from under R$300 in September 2016 to over R$1.1M
--         by early 2018. The growth_pct values at the very start and end
--         of the series are statistical artifacts, not real business
--         swings: November 2016 has zero orders (pre-launch pilot phase),
--         and September 2018 (R$166) is a partial final month, not a
--         genuine collapse. Read growth_pct only within Jan 2017-Aug 2018.
-- =============================================================================


WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp)::date AS month,
        SUM(oi.price + oi.freight_value) AS revenue
    FROM core.orders o
    JOIN core.order_items oi ON oi.order_id = o.order_id
    -- Canceled/unavailable orders never generated real revenue.
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1
)
SELECT
    month,
    ROUND(revenue, 2) AS revenue,
    ROUND(revenue - LAG(revenue) OVER (ORDER BY month), 2) AS revenue_change,
    ROUND(
        100.0 * (revenue - LAG(revenue) OVER (ORDER BY month)) / LAG(revenue) OVER (ORDER BY month), 1
    ) AS growth_pct
FROM monthly_revenue
ORDER BY month;
