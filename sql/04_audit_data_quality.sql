-------------------------------------------------------------------------------------
------------------------ UNICITY OF PRIMARY KEYS ---------------------------------
-------------------------------------------------------------------------------------

-- customers
--- customer_id
SELECT COUNT(DISTINCT customer_id) AS distinct_key, 
    COUNT(customer_id) AS key, 
    COUNT(DISTINCT customer_id) = COUNT(customer_id) AS primary_key_constraints_respected
FROM staging.customers
;

-- orders
--- order_id
SELECT COUNT(DISTINCT order_id) AS distinct_key, 
    COUNT(order_id) AS key, 
    COUNT(DISTINCT order_id) = COUNT(order_id) AS primary_key_constraints_respected
FROM staging.orders
;

-- order_items
--- (order_id, order_item_id)
SELECT COUNT(DISTINCT (order_id, order_item_id)) AS distinct_key, 
    COUNT((order_id, order_item_id)) AS key, 
    COUNT(DISTINCT (order_id, order_item_id)) = COUNT((order_id, order_item_id)) AS primary_key_constraints_respected
FROM staging.order_items
;

-- order_payments
--- (order_id, payment_sequential)
SELECT COUNT(DISTINCT (order_id, payment_sequential)) AS distinct_key, 
    COUNT((order_id, payment_sequential)) AS key, 
    COUNT(DISTINCT (order_id, payment_sequential)) = COUNT((order_id, payment_sequential)) AS primary_key_constraints_respected
FROM staging.order_payments
;

-- order_reviews
--- review_id
SELECT COUNT(DISTINCT review_id) AS distinct_key, 
    COUNT(review_id) AS key, 
    COUNT(DISTINCT review_id) = COUNT(review_id) AS primary_key_constraints_respected
FROM staging.order_reviews
;

--- order_id
SELECT COUNT(DISTINCT order_id) AS distinct_key, 
    COUNT(order_id) AS key, 
    COUNT(DISTINCT order_id) = COUNT(order_id) AS primary_key_constraints_respected
FROM staging.order_reviews
;

--- (review_id, order_id)
SELECT COUNT(DISTINCT (review_id, order_id)) AS distinct_key, 
    COUNT((review_id, order_id)) AS key, 
    COUNT(DISTINCT (review_id, order_id)) = COUNT((review_id, order_id)) AS primary_key_constraints_respected
FROM staging.order_reviews
;

-- products
--- product_id
SELECT COUNT(DISTINCT product_id) AS distinct_key, 
    COUNT(product_id) AS key, 
    COUNT(DISTINCT product_id) = COUNT(product_id) AS primary_key_constraints_respected
FROM staging.products
;

-- sellers
--- seller_id
SELECT COUNT(DISTINCT seller_id) AS distinct_key, 
    COUNT(seller_id) AS key, 
    COUNT(DISTINCT seller_id) = COUNT(seller_id) AS primary_key_constraints_respected
FROM staging.sellers
;

-- geolocation
--- geolocation_zip_code_prefix
SELECT COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_key, 
    COUNT(geolocation_zip_code_prefix) AS key, 
    COUNT(DISTINCT geolocation_zip_code_prefix) = COUNT(geolocation_zip_code_prefix) AS primary_key_constraints_respected
FROM staging.geolocation
;

--- (geolocation_zip_code_prefix, geolocation_city, geolocation_state)
--> needs transformation to have unique values for a given geolocation_zip_code_prefix (to join tables)
SELECT COUNT(DISTINCT (geolocation_zip_code_prefix, geolocation_city, geolocation_state)) AS distinct_key, 
    COUNT((geolocation_zip_code_prefix, geolocation_city, geolocation_state)) AS key, 
    COUNT(DISTINCT (geolocation_zip_code_prefix, geolocation_city, geolocation_state)) = COUNT((geolocation_zip_code_prefix, geolocation_city, geolocation_state)) AS primary_key_constraints_respected
FROM staging.geolocation
;

-- product_category_translation
--- product_category_name
SELECT COUNT(DISTINCT product_category_name) AS distinct_key, 
    COUNT(product_category_name) AS key, 
    COUNT(DISTINCT product_category_name) = COUNT(product_category_name) AS primary_key_constraints_respected
FROM staging.product_category_translation
;


-------------------------------------------------------------------------------------
------------------------ INTÉGRITÉ RÉFÉRENTIELLE (CLÉS ÉTRANGÈRES ORPHELINES) ---------------------------------
-------------------------------------------------------------------------------------

-- orders.customer_id in customers.customer_id
SELECT o.customer_id
FROM staging.orders o
LEFT JOIN staging.customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- order_items.order_id in orders.order_id
SELECT oi.order_id
FROM staging.order_items oi
LEFT JOIN staging.orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- order_items.product_id in products.product_id
SELECT DISTINCT oi.product_id
FROM staging.order_items oi
LEFT JOIN staging.products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- order_items.seller_id in sellers.seller_id
SELECT DISTINCT oi.seller_id
FROM staging.order_items oi
LEFT JOIN staging.sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

-- order_payments.order_id in orders.order_id
SELECT op.order_id
FROM staging.order_payments op
LEFT JOIN staging.orders o ON op.order_id = o.order_id
WHERE o.order_id IS NULL;

-- order_reviews.order_id in orders.order_id
SELECT orv.order_id
FROM staging.order_reviews orv
LEFT JOIN staging.orders o ON orv.order_id = o.order_id
WHERE o.order_id IS NULL;

-- products.product_category_name in product_category_translation.product_category_name
SELECT DISTINCT p.product_category_name
FROM staging.products p
LEFT JOIN staging.product_category_translation t 
  ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;

-- customers.customer_zip_code_prefix in geolocation.geolocation_zip_code_prefix
SELECT DISTINCT c.customer_zip_code_prefix
FROM staging.customers c
LEFT JOIN staging.geolocation g 
  ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
WHERE g.geolocation_zip_code_prefix IS NULL;

-- sellers.seller_zip_code_prefix in geolocation.geolocation_zip_code_prefix
SELECT DISTINCT s.seller_zip_code_prefix
FROM staging.sellers s
LEFT JOIN staging.geolocation g 
  ON s.seller_zip_code_prefix = g.geolocation_zip_code_prefix
WHERE g.geolocation_zip_code_prefix IS NULL;

-------------------------------------------------------------------------------------
------------------------ MISSING VALUES (NULL) ---------------------------------
-------------------------------------------------------------------------------------

-- orders
--- order_approved_at
SELECT COUNT(*)
FROM staging.orders
WHERE order_approved_at IS NULL
;

--- order_delivered_carrier_date
SELECT COUNT(*)
FROM staging.orders
WHERE order_delivered_carrier_date IS NULL
;

--- order_delivered_customer_date
SELECT COUNT(*)
FROM staging.orders
WHERE order_delivered_customer_date IS NULL
;

-- orders_reviews
--- review_comment_title
SELECT COUNT(*)
FROM staging.order_reviews
WHERE review_comment_title IS NULL
;

--- review_comment_message
SELECT COUNT(*)
FROM staging.order_reviews
WHERE review_comment_message IS NULL
;

-- multiple representation of emptiness
SELECT
  COUNT(*) FILTER (WHERE review_comment_title = ' ')   AS empty_string_title,
  COUNT(*) FILTER (WHERE review_comment_message = ' ') AS empty_string_message
FROM staging.order_reviews
;

-- products
--- product_category_name
SELECT COUNT(*)
FROM staging.products
WHERE product_category_name IS NULL
;

--- product_name_lenght
SELECT COUNT(*)
FROM staging.products
WHERE product_name_lenght IS NULL
;

--- product_description_lenght
SELECT COUNT(*)
FROM staging.products
WHERE product_description_lenght IS NULL
;

--- product_photos_qty
SELECT COUNT(*)
FROM staging.products
WHERE product_photos_qty IS NULL
;

--- product_weight_g
SELECT COUNT(*)
FROM staging.products
WHERE product_weight_g IS NULL
;

--- product_length_cm
SELECT COUNT(*)
FROM staging.products
WHERE product_length_cm IS NULL
;

--- product_height_cm
SELECT COUNT(*)
FROM staging.products
WHERE product_height_cm IS NULL
;

--- product_width_cm
SELECT COUNT(*)
FROM staging.products
WHERE product_width_cm IS NULL
;

-- verify is the NULL values in one column is also NULL for the others (610)
SELECT COUNT(*) AS fully_incomplete_sheet
FROM staging.products
WHERE product_category_name IS NULL
  AND product_name_lenght IS NULL
  AND product_description_lenght IS NULL
  AND product_photos_qty IS NULL;

-- verify is the NULL values in one column is also NULL for the others (2)
SELECT COUNT(*) AS fully_incomplete_sheet
FROM staging.products
WHERE product_weight_g IS NULL
  AND product_length_cm IS NULL
  AND product_height_cm IS NULL
  AND product_width_cm IS NULL;

-- geolocation
--- geolocation_lat
SELECT COUNT(*)
FROM staging.geolocation
WHERE geolocation_lat IS NULL
;

--- geolocation_lng
SELECT COUNT(*)
FROM staging.geolocation
WHERE geolocation_lng IS NULL
;

-- customers
--- customer_id
SELECT COUNT(*)
FROM staging.customers
WHERE customer_id IS NULL
;

--- customer_unique_id
SELECT COUNT(*)
FROM staging.customers
WHERE customer_unique_id IS NULL
;

--- customer_zip_code_prefix
SELECT COUNT(*)
FROM staging.customers
WHERE customer_zip_code_prefix IS NULL
;

--- customer_city
SELECT COUNT(*)
FROM staging.customers
WHERE customer_city IS NULL
;

--- customer_state
SELECT COUNT(*)
FROM staging.customers
WHERE customer_state IS NULL
;

-- order_items
--- price
SELECT COUNT(*)
FROM staging.order_items
WHERE price IS NULL
;

--- freight_value
SELECT COUNT(*)
FROM staging.order_items
WHERE freight_value IS NULL
;

--- shipping_limit_date
SELECT COUNT(*)
FROM staging.order_items
WHERE shipping_limit_date IS NULL
;

-- order_payments
--- payment_type
SELECT COUNT(*)
FROM staging.order_payments
WHERE payment_type IS NULL
;

--- payment_value
SELECT COUNT(*)
FROM staging.order_payments
WHERE payment_value IS NULL
;

--- payment_installments
SELECT COUNT(*)
FROM staging.order_payments
WHERE payment_installments IS NULL
;

-------------------------------------------------------------------------------------
------------------------ COHÉRENCE LOGIQUE ---------------------------------
-------------------------------------------------------------------------------------

-- orders approved before payment
SELECT order_id, order_purchase_timestamp, order_approved_at
FROM staging.orders
WHERE order_approved_at < order_purchase_timestamp;

-- delivered to the carrier before being approved
SELECT order_id, order_approved_at, order_delivered_carrier_date
FROM staging.orders
WHERE order_delivered_carrier_date < order_approved_at;

-- delivered to the client before being delivered to the carrier
SELECT order_id, order_delivered_carrier_date, order_delivered_customer_date
FROM staging.orders
WHERE order_delivered_customer_date < order_delivered_carrier_date;

-- being marked as "delivered" without the date when it was delivered to the client
SELECT order_id, order_status, order_delivered_customer_date
FROM staging.orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- price or freight value <= 0
SELECT order_id, order_item_id, price, freight_value
FROM staging.order_items
WHERE price <= 0 OR freight_value < 0;

-- payment value <= 0
SELECT order_id, payment_sequential, payment_value
FROM staging.order_payments
WHERE payment_value <= 0;

-- verify the payment type as 0 amount is legitimate for some types
SELECT payment_type, COUNT(*) AS n, MIN(payment_value) AS min_value
FROM staging.order_payments
WHERE payment_value = '0.00'
GROUP BY payment_type;

-- payment installments <= 0
SELECT order_id, payment_installments
FROM staging.order_payments
WHERE payment_installments <= 0;

-- delivered without payment
SELECT o.order_id
FROM staging.orders o
LEFT JOIN staging.order_payments op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
  AND op.order_id IS NULL;

-- review score not in the interval [1,5]
SELECT DISTINCT review_score
FROM staging.order_reviews
WHERE review_score NOT BETWEEN '1' AND '5';

-- multiple reviews for one order
SELECT order_id, COUNT(*) AS nb_reviews
FROM staging.order_reviews
GROUP BY order_id
HAVING COUNT(*) > 1;

-- delivery date before purchase date
SELECT order_id, order_purchase_timestamp, order_estimated_delivery_date
FROM staging.orders
WHERE order_estimated_delivery_date < order_purchase_timestamp;

-------------------------------------------------------------------------------------
------------------------ DOUBLONS STRICTS ---------------------------------
-------------------------------------------------------------------------------------

-- geolocation : all features identical
SELECT *, COUNT(*) AS nb_doublons
FROM staging.geolocation
GROUP BY geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, 
         geolocation_city, geolocation_state
HAVING COUNT(*) > 1;

-- geolocation : multiple different (lat/lng) for one zip code
SELECT geolocation_zip_code_prefix, COUNT(*) AS nb_lignes, 
       COUNT(DISTINCT geolocation_lat || '_' || geolocation_lng) AS nb_coords_distinctes
FROM staging.geolocation
GROUP BY geolocation_zip_code_prefix
HAVING COUNT(DISTINCT geolocation_lat || '_' || geolocation_lng) > 1
ORDER BY nb_lignes DESC;

-- orders : all features identical
SELECT *, COUNT(*) AS nb_doublons
FROM staging.orders
GROUP BY order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date
HAVING COUNT(*) > 1;

-- customers : all features identical
SELECT *, COUNT(*) AS nb_doublons
FROM staging.customers
GROUP BY customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state
HAVING COUNT(*) > 1;

-- order_items : all features identical
SELECT *, COUNT(*) AS nb_doublons
FROM staging.order_items
GROUP BY order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value
HAVING COUNT(*) > 1;

-- order_payments : all features identical
SELECT *, COUNT(*) AS nb_doublons
FROM staging.order_payments
GROUP BY order_id, payment_sequential, payment_type, payment_installments, payment_value
HAVING COUNT(*) > 1;

-- products : all features identical
SELECT *, COUNT(*) AS nb_doublons
FROM staging.products
GROUP BY product_id, product_category_name, product_name_lenght, product_description_lenght, product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm
HAVING COUNT(*) > 1;

-- sellers : all features identical
SELECT *, COUNT(*) AS nb_doublons
FROM staging.sellers
GROUP BY seller_id, seller_zip_code_prefix, seller_city, seller_state
HAVING COUNT(*) > 1;

