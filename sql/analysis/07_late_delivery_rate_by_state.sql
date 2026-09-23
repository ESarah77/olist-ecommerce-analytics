-- =============================================================================
-- Business question: Which customer states have the highest rate of late
--                     deliveries?
-- Why it matters: Points logistics investment (carrier renegotiation,
--                  regional warehouses) toward the states where the
--                  delivery promise is least reliable.
-- Technique: CTE, CASE, HAVING with a minimum volume threshold.
-- Answer: Late-delivery rates range from 23.9% in Alagoas (AL) to 2.9% in
--         Rondônia (RO); the worst-performing states cluster in the
--         North/Northeast, consistent with their distance from the
--         Southeast where most sellers are based.
-- Note: customer_state already lives on core.customers — no join to
--       core.geolocation is needed to answer this question; geolocation
--       would only be required to plot results on a map.
-- =============================================================================


WITH delivered AS (
    SELECT
        c.customer_state,
        o.order_id,
        CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
             THEN 1 ELSE 0 END AS is_late
    FROM core.orders o
    JOIN core.customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    customer_state,
    COUNT(*) AS nb_orders,
    SUM(is_late) AS nb_late_orders,
    ROUND(100.0 * SUM(is_late) / COUNT(*), 1) AS late_rate_pct
FROM delivered
GROUP BY customer_state
-- Minimum volume threshold: avoids a state with a handful of orders
-- producing a misleadingly extreme (0% or 100%) late rate.
HAVING COUNT(*) >= 30
ORDER BY late_rate_pct DESC;
