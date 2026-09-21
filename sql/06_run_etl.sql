-- =============================================================================
-- Runs the full staging -> core ETL in the order required by foreign key
-- dependencies. Run from the repository root with:
--   psql -d olist -f sql/06_run_etl.sql
-- =============================================================================

BEGIN;

\i sql/etl/01_product_category_translation.sql
\i sql/etl/02_geolocation.sql
\i sql/etl/03_customers.sql
\i sql/etl/04_sellers.sql
\i sql/etl/05_products.sql
\i sql/etl/06_orders.sql
\i sql/etl/07_order_items.sql
\i sql/etl/08_order_payments.sql
\i sql/etl/09_order_reviews.sql

COMMIT;
