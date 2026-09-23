-- =============================================================================
-- Business question: What share of customers place more than one order?
-- Why it matters: A very low repeat rate reframes the whole business model —
--                  growth depends on continuously acquiring new customers
--                  rather than on retaining existing ones, which changes
--                  where marketing budget should go.
-- Technique: subquery, COUNT DISTINCT, FILTER clause.
-- Answer: Only 3.12% of Olist's 96,096 unique customers (2,997) place more
--         than one order — growth relies almost entirely on acquiring new
--         customers, not on retaining existing ones.
-- Note: customer_unique_id is used rather than customer_id, since Olist
--       assigns a new customer_id to every order (stage 4 exploration) —
--       customer_id alone would make every customer look like a one-time
--       buyer by construction.
-- =============================================================================


SELECT
    COUNT(*) AS total_unique_customers,
    COUNT(*) FILTER (WHERE nb_orders > 1) AS recurring_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE nb_orders > 1) / COUNT(*), 2) AS recurring_customer_pct
FROM (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS nb_orders
    FROM core.customers c
    JOIN core.orders o ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
) customer_order_counts;
