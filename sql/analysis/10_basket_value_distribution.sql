-- =============================================================================
-- Business question: What is the average order value, and how spread out
--                     is that distribution?
-- Why it matters: An average alone can hide very different realities (a
--                  narrow distribution vs a few huge orders pulling the
--                  mean up); percentiles give a truer picture for pricing
--                  and promotion decisions.
-- Technique: CTE, PERCENTILE_CONT (ordered-set aggregate function).
-- Answer: The average basket is R$160.24 but the median is only R$105.28,
--         a right-skewed distribution pulled up by a small share of large
--         orders, including one outlier worth R$13,664.08.
-- =============================================================================


WITH order_value AS (
    SELECT
        o.order_id,
        SUM(oi.price + oi.freight_value) AS order_total
    FROM core.orders o
    JOIN core.order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY o.order_id
)
SELECT
    ROUND(AVG(order_total), 2) AS avg_basket_value,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY order_total)::numeric, 2) AS p25_basket_value,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY order_total)::numeric, 2) AS median_basket_value,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY order_total)::numeric, 2) AS p75_basket_value,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY order_total)::numeric, 2) AS p95_basket_value,
    ROUND(MAX(order_total), 2) AS max_basket_value
FROM order_value;
