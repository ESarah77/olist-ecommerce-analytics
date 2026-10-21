# Power BI Dashboard — Model, Measures and Validation

This document describes how the Power BI dashboard is built on top of the PostgreSQL `core` schema, how each KPI is defined, and how every figure was reconciled against the SQL reference analyses ([`sql/analysis/`](../sql/analysis/)).

- **File**: [`powerbi/olist_dashboard.pbix`](../powerbi/olist_dashboard.pbix) (Power BI Desktop, Windows only)
- **Source**: PostgreSQL, `core` tables plus the [`reporting.orders_enriched`](../sql/reporting/orders_enriched.sql) view
- **Connection mode**: Import (the data is embedded in the `.pbix`)

## 1. Architecture: who does what

| Layer | Responsibility | Why |
|---|---|---|
| **SQL** (`reporting.orders_enriched`) | Business rules already validated in the SQL analyses: one review per order, scope flags, delivery durations | Single source of truth; Power BI figures can be reconciled with SQL results |
| **Power Query** | Light shaping only: column types, unused columns removed, unused tables not loaded | Business logic stays versioned in SQL, not hidden in the tool |
| **DAX** | KPIs (measures) that must react to filters (year, state, category, seller) | A measure is recalculated for each filter context; SQL cannot do that |

## 2. Data model

A star-like model centred on `OrderItems` (one row per order item, the grain of revenue).

| Table | Grain | Role |
|---|---|---|
| `OrderItems` | 1 row per order item | Fact table (price, freight) |
| `Orders` (`reporting.orders_enriched`) | 1 row per order | Order dimension and delivery / satisfaction KPIs |
| `Products` | 1 row per product | Dimension |
| `ProductCategories` | 1 row per category | Dimension (English category names) |
| `Sellers` | 1 row per seller | Dimension |
| `Dates` | 1 row per day | Calendar, created in DAX, marked as date table |

Relationships, all one-to-many with single-direction filtering (from the "one" side to the "many" side):

| "One" side | "Many" side |
|---|---|
| `Orders[order_id]` | `OrderItems[order_id]` |
| `Products[product_id]` | `OrderItems[product_id]` |
| `Sellers[seller_id]` | `OrderItems[seller_id]` |
| `ProductCategories[product_category_name]` | `Products[product_category_name]` |
| `Dates[Date]` | `Orders[order_purchase_date]` |

`customers`, `order_reviews`, `order_payments` and `geolocation` are intentionally **not loaded**: customers are merged into the order view (`customer_id` is unique per order), and reviews / payments have a different grain than an order, which would create double counting if related to `OrderItems`.

## 3. Measure dictionary

| Measure | Business definition | DAX |
|---|---|---|
| `Revenue` | Item price + freight, excluding canceled / unavailable orders | `CALCULATE(SUM(OrderItems[price]) + SUM(OrderItems[freight_value]), Orders[is_revenue_order] = 1)` |
| `Nb Orders` | Distinct orders with at least one item, same scope as revenue | `CALCULATE(DISTINCTCOUNT(OrderItems[order_id]), Orders[is_revenue_order] = 1)` |
| `Avg Basket` | Revenue per order | `DIVIDE([Revenue], [Nb Orders])` |
| `Revenue % of Total` | Share of total revenue across all categories | `DIVIDE([Revenue], CALCULATE([Revenue], ALL(ProductCategories)))` |
| `Top 10 Categories Share` | Revenue share of the 10 best categories | `VAR Top10 = TOPN(10, ALL(ProductCategories[product_category_name_english]), [Revenue])` then `DIVIDE(CALCULATE([Revenue], Top10), CALCULATE([Revenue], ALL(ProductCategories)))` |
| `Delivered Orders` | Orders delivered with a known delivery date | `SUM(Orders[is_delivered])` |
| `Late Rate` | Delivered orders arriving after the estimated date | `DIVIDE(SUM(Orders[is_late]), SUM(Orders[is_delivered]))` |
| `Avg Delivery Days` | Purchase to delivery, delivered orders | `AVERAGE(Orders[delivery_days])` |
| `Avg Estimated Days` | Purchase to estimated delivery date | `AVERAGE(Orders[estimated_delivery_days])` |
| `Avg Review Score` | Average latest review score, delivered orders | `CALCULATE(AVERAGE(Orders[review_score]), Orders[is_delivered] = 1)` |
| `Dissatisfaction Rate` | Share of reviewed delivered orders scored 1 to 3 | `DIVIDE(CALCULATE(COUNTROWS(Orders), Orders[is_delivered] = 1, Orders[review_score] IN {1, 2, 3}), CALCULATE(COUNT(Orders[review_score]), Orders[is_delivered] = 1))` |
| `Unique Customers` | Distinct `customer_unique_id` | `DISTINCTCOUNT(Orders[customer_unique_id])` |
| `Recurring Customers` | Customers with more than one order | `COUNTROWS(FILTER(VALUES(Orders[customer_unique_id]), CALCULATE(COUNTROWS(Orders)) > 1))` |
| `Recurring Rate` | Recurring / unique customers | `DIVIDE([Recurring Customers], [Unique Customers])` |
| `Avg Review (items)` | Average review score weighted by order item | `AVERAGE(OrderItems[Order Review Score])` |
| `Reviewed Orders` | Distinct orders with a review (used for volume thresholds) | `CALCULATE(DISTINCTCOUNT(OrderItems[order_id]), OrderItems[Order Review Score] >= 1)` |
| `Seller Rank (worst / best)` | Rank among sellers with at least 20 reviewed orders | `IF([Reviewed Orders] >= 20, RANKX(FILTER(ALL(Sellers), [Reviewed Orders] >= 20), [Avg Review (items)], , ASC))` (`DESC` for best) |

Calculated columns: `Orders[Delivery Status]` (`Not delivered` / `Late` / `On time`, built with `SWITCH(TRUE(), ...)`) and `OrderItems[Order Review Score] = RELATED(Orders[review_score])`.

`Dates` table: `CALENDAR` between the first and last purchase month, with `Year` and `Month Start` columns.

## 4. Design decisions

- **Order counts are taken from `OrderItems`**, not `Orders`: a few orders have no item, and counting them would distort the average basket (same behaviour as SQL query 10).
- **Date filtering only on the line chart**: the monthly series covers Jan 2017 to Aug 2018, since 2016 is a pilot phase (November 2016 has no order) and September 2018 is a partial month. The KPI cards keep the full period so they match the SQL totals.
- **Recurring-customer KPIs ignore the Year slicer** (interaction disabled): a customer who orders in 2017 and again in 2018 would otherwise look non-recurring when a single year is selected.
- **`ALL(Sellers)` (whole table) in the seller rank**: `ALL(Sellers[seller_id])` only removes the filter on one column, so a `seller_state` column in the table would split the ranking by state.
- **Calculated column for the review score on `OrderItems`**: computing `RELATED(...)` inside an iterator for every seller made the seller tables too slow on the full period; storing it once in a column makes the measures simple aggregations.
- **Item-weighted averages for category and seller review scores**: same definition as SQL queries 08 and 09, so the figures reconcile exactly. An order-weighted average would differ slightly.

## 5. Validation against the SQL reference

Every figure below was checked in Power BI (full period, no slicer selected) against the SQL result.

| KPI | Power BI | SQL reference |
|---|---|---|
| Revenue | R$ 15.74M | 15,735,527.03 (revenue scope query) |
| Orders | 98,199 | 98,199 |
| Average basket | R$ 160.24 | 160.24 (analysis 10) |
| Orders per year (2016 / 2017 / 2018) | 329 / 45,101 / 54,011 | same (total 99,441) |
| Top 10 categories share | 62.3% | 62.33% (analysis 06) |
| Average delivery / estimated delivery | 12.5 / 24.4 days | 12.5 / 24.4 (analysis 01) |
| Late rate | 8.1% | 100% − 91.9% on time (analysis 01) |
| Average review score (delivered) | 4.16 | 4.16 |
| Dissatisfaction, late vs on time | 65.4% vs 17.2% | 65.4% vs 17.2% (analysis 02) |
| Average score, late vs on time | 2.57 vs 4.29 | 2.57 vs 4.29 (analysis 02) |
| Late rate by state | AL 23.9% ... RO 2.9% | same (analysis 07) |
| Unique / recurring customers, rate | 96,096 / 2,997 / 3.12% | same (analysis 04) |
| Lowest / highest rated categories | office_furniture 3.49 / books_general_interest 4.45 | same (analysis 08) |
| Lowest / highest rated sellers (min. 20 orders) | 2.10 ... 2.79 / 5.00 ... 4.81 | same (analysis 09) |

The year slicer was also checked on 2017 (revenue, late rate, delivery days, review score) against SQL queries filtered on that year.

## 6. Limitations

- **Delivery-time trend at the end of the series**: the average delivery and estimated times drop in mid-2018. This is most likely a data-extraction effect: orders placed shortly before the end of the dataset and not yet delivered are excluded, so only the fastest deliveries remain. The trend should not be read as a real improvement.
- **Snapshot data**: Import mode embeds a copy of the data; refreshing requires a PostgreSQL database with the same schema.
- **Not covered**: RFM segmentation, basket distribution, payments and geolocation maps stay in the SQL analyses; the dashboard is kept deliberately concise.
- **Windows only**: Power BI Desktop does not run on Linux, so the `.pbix` is built and opened on Windows.
