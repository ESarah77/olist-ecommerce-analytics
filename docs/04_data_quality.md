# Data Quality Audit

**Stage 4 of the project.** This document *observes and documents* data quality issues in the `staging` schema. No data is modified here: structural rules are declared in the `core` schema (stage 5) and corrections are applied by the ETL (stage 6).

- **Source**: Brazilian E-Commerce Public Dataset by Olist (9 raw CSV files loaded as-is into `staging`).
- **Queries**: [`sql/04_audit_data_quality.sql`](../sql/04_audit_data_quality.sql)
- **Audit scope**: primary key uniqueness, referential integrity, missing values, logical consistency, exact duplicates.

---

## Executive summary

The dataset is globally clean. Nine issues require an explicit decision; none of them invalidates the project.

| # | Area | Finding | Volume | Decision | Stage |
|---|---|---|---|---|---|
| 1 | Uniqueness | `order_reviews` has no single-column PK | 814 dup. `review_id`, 551 dup. `order_id` | Composite PK `(review_id, order_id)` | 5 |
| 2 | Uniqueness | `geolocation` has no PK at all | 1,000,163 rows / 19,015 zip prefixes | Rebuild as 1 row per zip prefix | 6 |
| 3 | Referential | 2 product categories have no English translation | 2 / 71 (0.006% of products) | Manual mapping of the 2 labels | 6 |
| 4 | Referential | Zip prefixes absent from `geolocation` | 157 customer / 7 seller prefixes | No FK; coordinates left NULL | 5 |
| 5 | Missing | `products` descriptive attributes missing | 610 rows (1.85%) + 2 rows | Category → `'unknown'`, rest kept NULL | 6 |
| 6 | Consistency | Shipping timestamps out of order | 1,382 rows (1.39%) | Boolean flag, rows kept | 6 |
| 7 | Consistency | `delivered` orders with no delivery date | 8 rows (0.008%) | Kept, excluded from delivery scope | 6 / 8 |
| 8 | Consistency | `payment_installments = 0` on credit card | 2 rows (0.002%) | Imputed to 1 | 6 |
| 9 | Consistency | Several reviews for one order | 547 orders (0.55%) | Keep the most recent review | 6 / 8 |

---

## 1. Primary key uniqueness

**Why**: the raw CSVs carry no constraints. Each candidate key must be verified before it can be declared a `PRIMARY KEY` in `core`, otherwise the ETL fails or silently duplicates rows through joins.

| Table | Candidate key | Unique | Rows / distinct |
|---|---|---|---|
| `customers` | `customer_id` | Yes | — |
| `orders` | `order_id` | Yes | — |
| `order_items` | `(order_id, order_item_id)` | Yes | — |
| `order_payments` | `(order_id, payment_sequential)` | Yes | — |
| `order_reviews` | `review_id` | **No** | 99,224 / 98,410 |
| `order_reviews` | `order_id` | **No** | 99,224 / 98,673 |
| `order_reviews` | `(review_id, order_id)` | Yes | — |
| `products` | `product_id` | Yes | — |
| `sellers` | `seller_id` | Yes | — |
| `geolocation` | `geolocation_zip_code_prefix` | **No** | 1,000,163 / 19,015 |
| `geolocation` | `(zip_code_prefix, city, state)` | **No** | 1,000,163 / 27,912 |
| `product_category_name_translation` | `product_category_name` | Yes | — |

### 1.1 `order_reviews` — two distinct anomalies

**Interpretation.** These are two different phenomena, not one:
- A repeated `review_id` (814 cases) means **one review answer was attached to several orders** — typically a customer reviewing a purchase that was split into multiple orders.
- A repeated `order_id` (551 cases) means **one order received several review answers** — a customer answering the satisfaction survey more than once.

The pair `(review_id, order_id)` is unique, so the table's real grain is *one review answer per order*, not *one review per order*.

**Action.** Stage 5: declare `PRIMARY KEY (review_id, order_id)` on `core.order_reviews`. Stage 6 and 8: any analysis or ML feature that requires *one satisfaction score per order* must deduplicate explicitly — see [section 4.7](#47-several-reviews-for-the-same-order--547-orders).

### 1.2 `geolocation` — no primary key

**Interpretation.** `geolocation` is a raw dump of GPS points, several per zip prefix (52 rows per prefix on average). The `(zip, city, state)` combination producing 27,912 distinct values against 19,015 prefixes also reveals **inconsistent city spellings** for a single prefix (accents, abbreviations, typos).

**Action.** Stage 6: `core.geolocation` is rebuilt as one row per `zip_code_prefix`, which becomes its primary key — see [section 5.1](#51-geolocation).

---

## 2. Referential integrity

**Why**: a foreign key pointing to a non-existent parent row means rows silently disappear on joins, or the FK constraint cannot be created in `core`.

| Foreign key | Orphans |
|---|---|
| `orders.customer_id` → `customers.customer_id` | 0 |
| `order_items.order_id` → `orders.order_id` | 0 |
| `order_items.product_id` → `products.product_id` | 0 |
| `order_items.seller_id` → `sellers.seller_id` | 0 |
| `order_payments.order_id` → `orders.order_id` | 0 |
| `order_reviews.order_id` → `orders.order_id` | 0 |
| `products.product_category_name` → `product_category_name_translation` | **2 labels** |
| `customers.customer_zip_code_prefix` → `geolocation` | **157 prefixes** |
| `sellers.seller_zip_code_prefix` → `geolocation` | **7 prefixes** |

The transactional backbone (orders, items, payments, reviews, customers, products, sellers) is fully referentially consistent. All six FK constraints can be declared in `core` without any preliminary cleaning.

### 2.1 Untranslated product categories

**Finding.** 2 category labels out of 71 have no row in the translation table: `portateis_cozinha_e_preparadores_de_alimentos` and `pc_gamer`.

**Interpretation.** This is a gap in the reference table, not in the transactional data. Left untreated, the English category column would be NULL for these products, which would push them out of every category-level analysis.

**Action (stage 6).** Add the two missing translations manually inside the ETL, then join. Concretely, the ETL loads the translation table *extended* by two rows:

```sql
-- sql/etl/product_category_translation.sql
INSERT INTO core.product_category_translation (category_name_pt, category_name_en)
SELECT product_category_name, product_category_name_english
FROM staging.product_category_name_translation
UNION ALL
VALUES
  ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_food_preparers'),
  ('pc_gamer', 'pc_gamer');
```

*Alternative considered and rejected*: falling back to the Portuguese label via `COALESCE`. It requires no manual input but leaves two Portuguese values inside a column documented as English, which is an inconsistency a reader would notice. Two manual rows cost one minute and keep the column homogeneous.

### 2.2 Zip prefixes with no geolocation coverage

**Finding.** 157 customer zip prefixes and 7 seller zip prefixes have no matching row in `geolocation`.

**Interpretation.** **This is not a blocking foreign key.** `geolocation` is an enrichment lookup table, not a parent entity: a customer or a seller exists as a business object regardless of whether GPS coordinates are available for their area. Declaring an FK here would force us to delete valid customers because of missing reference data, which would be a data quality decision driven by a schema artifact rather than by the business.

**Action.**
- Stage 5: **no FK constraint** from `customers` / `sellers` to `geolocation`.
- Stage 6: enrich coordinates through a `LEFT JOIN`; affected rows get `NULL` latitude and longitude.
- Stage 7: any geographic or distance-based analysis must handle those NULLs and report the coverage rate.

**Documented limitation**: geographic coverage is ~99% but not complete; distance-based metrics are computed on the covered subset.

---

## 3. Missing values (NULL)

**Why**: distinguishing *legitimate* NULLs (the event has not happened yet) from *defective* NULLs (the information should exist) determines which columns can be declared `NOT NULL` in `core` and which ones need imputation.

### 3.1 `orders` — timestamps

| Column | NULL | % |
|---|---|---|
| `order_approved_at` | 160 | 0.161% |
| `order_delivered_carrier_date` | 1,783 | 1.793% |
| `order_delivered_customer_date` | 2,965 | 2.982% |

**Interpretation.** These NULLs are **legitimate and informative**: they encode the order lifecycle stage. An order that is `canceled`, `processing` or `shipped` has genuinely never reached the delivery step. The increasing volume along the funnel (160 → 1,783 → 2,965) is consistent with orders dropping out at each stage. Cross-checking against `order_status` confirms the pattern, with one exception documented in [section 4.4](#44-delivered-orders-with-no-delivery-date--8-rows).

**Why this check matters** (it produces three concrete decisions):
1. These three columns **must remain nullable** in `core.orders` — a `NOT NULL` constraint would reject 3% of valid orders.
2. Delivery duration features are computable only where `order_delivered_customer_date IS NOT NULL`, which defines the scope of the ML dataset (stage 8).
3. Any average delivery time must be computed on delivered orders only, otherwise the denominator is wrong.

**Action.** No transformation. Nullable columns in `core`, explicit scope filters in stages 7 and 8.

### 3.2 `order_reviews` — free-text comments

| Column | NULL | % |
|---|---|---|
| `review_comment_title` | 87,656 | 88.342% |
| `review_comment_message` | 58,247 | 58.703% |

**Interpretation.** Optional survey fields; a high NULL rate is expected and carries no defect. The only real risk is having **two competing representations of emptiness** (`NULL` and `''`) in the same column, which would break any `IS NULL` filter.

**Action (stage 6).** Normalise with `NULLIF(TRIM(col), '')` so that a single representation of "no comment" exists. These columns are not used as ML features (see the leakage discussion in stage 8).

### 3.3 `products` — descriptive attributes

| Column | NULL | % |
|---|---|---|
| `product_category_name` | 610 | 1.851% |
| `product_name_lenght` | 610 | 1.851% |
| `product_description_lenght` | 610 | 1.851% |
| `product_photos_qty` | 610 | 1.851% |
| `product_weight_g` | 2 | 0.006% |
| `product_length_cm` | 2 | 0.006% |
| `product_height_cm` | 2 | 0.006% |
| `product_width_cm` | 2 | 0.006% |

**Interpretation.** The identical counts point to two blocks of rows rather than eight independent problems: 610 products whose catalogue sheet was never filled in, and 2 products whose physical dimensions were never measured.

**Action (stage 6).**
- `product_category_name` → replaced by `'unknown'`. Rationale: this column is a grouping dimension in most business analyses; leaving NULL would silently drop those products from `GROUP BY` reporting, whereas an explicit `'unknown'` category keeps the revenue visible and makes the gap auditable.
- The 6 other columns → **kept NULL, no imputation**. They are measurements, not dimensions. Imputing a mean weight would fabricate information and distort any freight or volume analysis. NULL is the honest encoding of "not measured".
- Stage 8: if `product_weight_g` or the dimensions are used as ML features, missingness is handled by the model or by an explicit indicator column, never by a silent mean.

### 3.4 Columns with no missing values

No NULL found in `geolocation` (lat, lng), `customers` (all columns), `order_items` (`price`, `freight_value`, `shipping_limit_date`), `order_payments` (`payment_type`, `payment_value`, `payment_installments`). These columns are declared `NOT NULL` in `core` (stage 5).

---

## 4. Logical consistency

**Why**: a row can satisfy every structural constraint and still be impossible from a business standpoint. These checks look for contradictions between columns of the same row, or across tables.

| Check | Rows | % |
|---|---|---|
| `order_approved_at` < `order_purchase_timestamp` | 0 | — |
| `order_delivered_carrier_date` < `order_approved_at` | 1,359 | 1.367% |
| `order_delivered_customer_date` < `order_delivered_carrier_date` | 23 | 0.023% |
| `order_status = 'delivered'` and no delivery date | 8 | 0.008% |
| `price <= 0` or `freight_value < 0` | 0 | — |
| `payment_value <= 0` | 9 | 0.009% |
| `payment_installments <= 0` | 2 | 0.002% |
| `delivered` order with no payment row | 1 | 0.001% |
| `review_score` outside [1,5] | 0 | — |
| `order_estimated_delivery_date` < `order_purchase_timestamp` | 0 | — |

Four checks return zero and require no treatment; they are kept in the audit because a passing check is itself a result, and each one justifies a `CHECK` constraint in `core` (stage 5).

### 4.1 Shipping before payment approval — 1,359 rows

**Interpretation.** The parcel was handed to the carrier before the payment approval timestamp was recorded. Two plausible causes: sellers shipping in anticipation of approval, or asynchronous logging of the approval event. The volume (1.37%) rules out both a marginal glitch and a systematic corruption — the rest of the row (customer, items, amounts, final delivery) remains perfectly usable.

### 4.2 Delivery to customer before handover to carrier — 23 rows

**Interpretation.** Physically impossible: at least one of the two timestamps is wrong. The volume is negligible.

### 4.3 Treatment for 4.1 and 4.2 — flagging

**Action (stage 6).** These 1,382 rows are **not deleted**. Deleting 1.4% of orders would remove valid revenue, valid customers and valid reviews because of a timestamp artefact, and would bias every commercial analysis. We also do not *correct* the timestamps: there is no way to recover the true value, and inventing one would be worse than keeping the anomaly visible.

Instead, the ETL computes a boolean column on `core.orders`:

```sql
-- computed in sql/etl/orders.sql
CASE
  WHEN order_delivered_carrier_date  < order_approved_at              THEN TRUE
  WHEN order_delivered_customer_date < order_delivered_carrier_date   THEN TRUE
  ELSE FALSE
END AS has_inconsistent_timestamps
```

This is the flagging principle: the row stays available for commercial analysis, and any query measuring an intermediate logistics duration adds `WHERE NOT has_inconsistent_timestamps`. The quality issue becomes an explicit, queryable attribute instead of a silent one.

Note that the end-to-end delay (`order_delivered_customer_date - order_purchase_timestamp`) stays valid for these rows, since only the intermediate timestamps are suspect. Only stage-to-stage durations are affected.

### 4.4 `delivered` orders with no delivery date — 8 rows

**Interpretation.** Contradiction between status and timestamps. The order exists commercially (it has items, a payment and often a review) but its delivery date is unrecoverable.

**Action.** Rows **kept** in `core.orders` (they carry real revenue), but excluded from every delivery-duration analysis and from the ML dataset through the scope filter `order_delivered_customer_date IS NOT NULL`, which is required anyway to compute the delay features. No dedicated treatment is needed: the natural scope condition of stages 7 and 8 already removes them. Documented so the 8-row gap between "delivered orders" and "orders with a measured delay" is explainable.

### 4.5 Zero or negative payment amounts — 9 rows

**Interpretation.** Before deciding, the payment type must be inspected, since a zero amount is legitimate for some types (a voucher fully covering a payment line) and defective for others.

In this dataset the affected rows are `not_defined` and `voucher` payment lines with a value of exactly 0 — there is no negative amount. These are **not errors**: an order total is the sum of its payment lines, and a zero line neither breaks the total nor inflates revenue.

**Action.** Rows kept. Stage 5: the constraint is `CHECK (payment_value >= 0)`, not `> 0` — an important distinction, as the stricter version would reject valid rows. Stage 7: order revenue is computed from `order_items` (`price + freight_value`) rather than from payments, which makes this issue irrelevant to the commercial analyses.

### 4.6 Zero instalments on a credit card — 2 rows

**Interpretation.** A credit card payment necessarily involves at least one instalment. Unlike section 4.5, there is no payment type that makes `0` meaningful here, so this is a genuine data entry error.

**Action (stage 6).** Impute to `1`, which is both the minimum possible value and the modal value of the column. The imputation is defensible because the true value is bounded below by 1 and the correction affects 2 rows out of 103,886. Stage 5: `CHECK (payment_installments >= 1)`.

```sql
GREATEST(payment_installments, 1) AS payment_installments
```

### 4.7 Several reviews for the same order — 547 orders

**Interpretation.** Confirms the grain discovered in [section 1.1](#11-order_reviews--two-distinct-anomalies): the survey allows multiple answers per order. This is the most consequential finding of the audit, because it directly determines the **ML target variable** (stage 8): without an explicit rule, joining orders to reviews duplicates orders and silently inflates the training set.

**Action (stage 6 / 8).** `core.order_reviews` keeps the full grain `(review_id, order_id)` — no information is destroyed. Deduplication happens in the analytical layer, keeping **the most recent review** per order:

```sql
-- inside the ML feature view, stage 8
SELECT DISTINCT ON (order_id) order_id, review_id, review_score, review_answer_timestamp
FROM core.order_reviews
ORDER BY order_id, review_answer_timestamp DESC, review_id;
```

*Rationale for "most recent" over "average"*: the target is a binary satisfaction label derived from a 1–5 ordinal scale. Averaging produces values (3.5) that correspond to no real customer answer and make the ≤3 / ≥4 threshold arbitrary. The latest answer is the customer's final stated opinion, stays on the native scale, and is a rule that can be stated in one sentence. The affected volume (0.55%) makes the two options statistically near-equivalent, so the more interpretable one wins.

### 4.8 Delivered order with no payment — 1 row

**Interpretation.** Isolated anomaly. The order was fulfilled but no payment line was recorded.

**Action.** Row kept. Since revenue is computed from `order_items` (see 4.5), this order contributes correctly to commercial analyses. Only payment-type analyses exclude it naturally, as it has no payment row to join. Documented; no treatment.

---

## 5. Exact duplicates

**Why**: identical rows repeated in a raw CSV are a load artefact. Left in place they inflate counts and, more insidiously, bias aggregates by weighting values according to how many times the line was dumped.

| Table | Fully duplicated rows |
|---|---|
| `geolocation` (all columns identical) | **128,174 duplicated groups** |
| `orders` | 0 |
| `customers` | 0 |
| `order_items` | 0 |
| `order_payments` | 0 |
| `products` | 0 |
| `sellers` | 0 |

Seven of the eight tables are duplicate-free, which allows the ETL to load them with a straightforward `INSERT ... SELECT` and no deduplication logic.

### 5.1 `geolocation`

Two distinct issues coexist in this table.

**Issue A — exact duplicates.** 128,174 coordinate combinations appear more than once. The same GPS point may be repeated dozens of times for a zip prefix.

**Issue B — multiple distinct points per zip.** 17,781 of the 19,015 zip prefixes (**93.5%**) have more than one distinct coordinate pair. This is expected: a zip *prefix* covers an area, not a point.

**Why A must be fixed before B.** Averaging the raw rows would weight each geographic point by its number of duplicated lines in the CSV — a technical artefact of the export, not a geographic reality. A point duplicated 50 times would pull the centroid toward itself. Deduplicating first makes the average a true centroid of the distinct known points. This is what "DISTINCT before aggregation" means.

**Action (stage 6).** `core.geolocation` is rebuilt as one row per zip prefix:

```sql
-- sql/etl/geolocation.sql
WITH distinct_points AS (
    SELECT DISTINCT
        geolocation_zip_code_prefix AS zip_code_prefix,
        geolocation_lat             AS lat,
        geolocation_lng             AS lng,
        geolocation_city            AS city,
        geolocation_state           AS state
    FROM staging.olist_geolocation_dataset
),
city_mode AS (
    SELECT
        zip_code_prefix,
        city,
        state,
        ROW_NUMBER() OVER (
            PARTITION BY zip_code_prefix
            ORDER BY COUNT(*) DESC, city
        ) AS rn
    FROM distinct_points
    GROUP BY zip_code_prefix, city, state
),
centroid AS (
    SELECT
        zip_code_prefix,
        AVG(lat) AS lat,
        AVG(lng) AS lng
    FROM distinct_points
    GROUP BY zip_code_prefix
)
INSERT INTO core.geolocation (zip_code_prefix, lat, lng, city, state)
SELECT c.zip_code_prefix, c.lat, c.lng, m.city, m.state
FROM centroid c
JOIN city_mode m
  ON m.zip_code_prefix = c.zip_code_prefix AND m.rn = 1;
```

The city and state are resolved by **mode** (most frequent value) rather than by an arbitrary `MIN()`, because the 27,912 distinct `(zip, city, state)` combinations found in section 1.2 are largely spelling variants of the same locality; the most frequent spelling is the best available canonical form. The deterministic tie-break on `city` keeps the ETL reproducible.

Result: 1,000,163 rows reduced to 19,015, with `zip_code_prefix` as a genuine primary key.

---

## 6. Consequences for the `core` schema (stage 5)

Constraints justified by this audit:

- **Primary keys**: `customers(customer_id)`, `orders(order_id)`, `order_items(order_id, order_item_id)`, `order_payments(order_id, payment_sequential)`, `order_reviews(review_id, order_id)`, `products(product_id)`, `sellers(seller_id)`, `geolocation(zip_code_prefix)`, `product_category_translation(category_name_pt)`.
- **Foreign keys**: the six transactional relations of section 2, all validated with 0 orphans. **No** FK toward `geolocation`.
- **Nullable**: `orders.order_approved_at`, `orders.order_delivered_carrier_date`, `orders.order_delivered_customer_date`, `products` measurement columns, `geolocation` coordinates on enriched tables.
- **CHECK constraints**: `price > 0`, `freight_value >= 0`, `payment_value >= 0`, `payment_installments >= 1`, `review_score BETWEEN 1 AND 5`.
- **Added ETL column**: `orders.has_inconsistent_timestamps BOOLEAN NOT NULL`.

---

## 7. Limitations of this audit

- **Coordinate plausibility not tested.** Latitude and longitude were checked for NULL but not against Brazil's bounding box; out-of-country points may remain in `core.geolocation`. Relevant only if distance-based features are introduced in stage 8.
- **Category label consistency not tested.** Free-text city names were addressed through the mode, but no fuzzy matching was performed on spelling variants; two spellings of the same city may survive as distinct values in `customers` and `sellers`.
- **Business plausibility of amounts not tested.** No outlier detection on `price`, `freight_value` or `payment_value`; extreme but valid-looking values are kept.
- **Single snapshot.** The dataset is a static export, so no freshness or incremental-load quality checks apply.
