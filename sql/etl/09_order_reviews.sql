-- =============================================================================
-- ETL: staging.order_reviews -> core.order_reviews
-- =============================================================================
-- Fix: review_comment_title / review_comment_message may contain empty
-- strings alongside genuine NULLs (stage 4, section 3.2). NULLIF(TRIM(...), '')
-- normalizes both to a single NULL representation, so a later
-- "IS NULL" filter is reliable.
--
-- No deduplication here: staging has neither a unique review_id nor a
-- unique order_id (814 / 551 duplicates, stage 4 section 1.1), but the
-- composite (review_id, order_id) is unique, which is the grain core.
-- order_reviews is built to preserve. Reducing to "one score per order"
-- (keeping the most recent review) happens only in the analytical / ML
-- layer (stage 7/8), never here — core keeps the full, lossless grain.
--
-- All staging columns are typed TEXT, so every value is explicitly cast to
-- the type expected by core.order_reviews (SMALLINT for the score,
-- TIMESTAMP for the two dates).
--
-- Must run AFTER 06_orders.sql (FK dependency).
-- =============================================================================

INSERT INTO core.order_reviews (
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
)
SELECT
    review_id::CHAR(32)                                        AS review_id,
    order_id::CHAR(32)                                         AS order_id,
    review_score::SMALLINT                                     AS review_score,
    NULLIF(TRIM(review_comment_title), '')::VARCHAR(100)       AS review_comment_title,
    NULLIF(TRIM(review_comment_message), '')::TEXT             AS review_comment_message,
    review_creation_date::TIMESTAMP                            AS review_creation_date,
    review_answer_timestamp::TIMESTAMP                         AS review_answer_timestamp
FROM staging.order_reviews;
