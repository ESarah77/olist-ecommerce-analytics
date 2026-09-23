
-- =============================================================================
-- Business question: How does actual delivery time compare to the delivery
--                     date Olist estimates to the customer at checkout?
-- Why it matters: If estimates are systematically too conservative, customers
--                  may be discouraged from buying (a visible "long wait"
--                  scares off conversions) even though the real experience
--                  is fast — a concrete lever for the ops/product team.
-- Technique: date arithmetic, FILTER clause, aggregate functions.
-- Answer: Actual delivery averages 12.5 days versus a 24.4-day estimate —
--         orders arrive 11.9 days earlier than promised on average, and
--         91.9% of deliveries beat or meet the estimated date.
-- =============================================================================


-- Scope: only orders that actually reached the customer. Orders flagged
-- has_inconsistent_timestamps are NOT excluded here: that flag concerns
-- intermediate carrier/approval timestamps, not the purchase-to-delivery
-- span computed below, which remains valid for those rows.
SELECT
    COUNT(*) AS delivered_orders,
    ROUND(AVG(order_delivered_customer_date::date - order_purchase_timestamp::date), 1)
        AS avg_actual_delivery_days,
    ROUND(AVG(order_estimated_delivery_date::date - order_purchase_timestamp::date), 1)
        AS avg_estimated_delivery_days,
    ROUND(AVG(order_estimated_delivery_date::date - order_delivered_customer_date::date), 1)
        AS avg_days_estimate_overshoots_actual,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE order_delivered_customer_date <= order_estimated_delivery_date)
        / COUNT(*), 1
    ) AS pct_delivered_on_or_before_estimate
FROM core.orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;
