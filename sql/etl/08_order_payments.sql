-- =============================================================================
-- ETL: staging.order_payments -> core.order_payments
-- =============================================================================
-- Fixes (stage 4, sections 4.5/4.6):
--   - payment_installments: 2 credit_card rows had 0 installments, which is
--     not a meaningful value for that payment type (unlike payment_value,
--     see below). GREATEST(payment_installments, 1) imputes the minimum
--     possible value; the true value is bounded below by 1, so this is a
--     safe correction, not a fabrication.
--   - payment_value: 9 rows at 0 on 'not_defined'/'voucher' payment types
--     are legitimate (a voucher can fully cover a payment line) and are
--     loaded as-is, matching the core CHECK (payment_value >= 0, not > 0).
--
-- All staging columns are typed TEXT, so every value is explicitly cast to
-- the type expected by core.order_payments before GREATEST() is applied
-- (comparing text values would sort lexicographically, not numerically).
--
-- Must run AFTER 06_orders.sql (FK dependency).
-- =============================================================================

INSERT INTO core.order_payments (
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
)
SELECT
    order_id::CHAR(32)                              AS order_id,
    payment_sequential::SMALLINT                    AS payment_sequential,
    payment_type::VARCHAR(20)                       AS payment_type,
    GREATEST(payment_installments::SMALLINT, 1)     AS payment_installments,
    payment_value::NUMERIC(10, 2)                   AS payment_value
FROM staging.order_payments;
