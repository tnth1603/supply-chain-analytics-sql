-- ============================================================
-- SUPPLY CHAIN ANALYTICS PROJECT
-- Script: 01_data_cleaning_and_modeling.sql
-- Description: 3-layer architecture — Landing, Staging, Marts
-- Database: PostgreSQL
-- Author: Tuan Thanh Thinh
-- ============================================================


-- ============================================================
-- LAYER 0 — CREATE SCHEMAS
-- ============================================================

CREATE SCHEMA IF NOT EXISTS landing;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS marts;


-- ============================================================
-- LAYER 1 — LANDING
-- Raw data loaded as-is from CSV. No transformations.
-- ============================================================

-- Move raw table into landing schema
ALTER TABLE supply_chain_final
SET SCHEMA landing;

-- Verify landing table
SELECT COUNT(*) AS total_raw_rows
FROM landing.supply_chain_final;


-- ============================================================
-- LAYER 2 — STAGING
-- Clean, standardise and split flat file into entity views.
-- ============================================================

-- ── STAGING.stg_transactions ─────────────────────────────────
CREATE OR REPLACE VIEW staging.stg_transactions AS
WITH source AS (
    SELECT *
    FROM landing.supply_chain_final
),
transactions_cleaned AS (
    SELECT
        -- Identity
        TRIM("Transaction ID")                              AS transaction_id,
        "Transaction Date"::DATE                            AS transaction_date,
        TRIM(LOWER("SKU"))                                  AS sku,
        TRIM(LOWER("Product Type"))                         AS product_type,
        TRIM(LOWER("Supplier Name"))                        AS supplier_name,
        TRIM(LOWER("Shipping Carriers"))                    AS shipping_carriers,

        -- Inventory measures
        ROUND(CAST("Price" AS NUMERIC), 2)                          AS price,
        "Availability"::INTEGER                             AS availability,
        "Number of Products Sold"::INTEGER                  AS number_of_products_sold,
        ROUND(CAST("Revenue Generated" AS NUMERIC), 2)              AS revenue_generated,
        "Stock Levels"::INTEGER                             AS stock_levels,
        "Order Quantities"::INTEGER                         AS order_quantities,

        -- Procurement measures
        "Lead Time"::INTEGER                                AS lead_time,
        "Lead Times"::INTEGER                               AS lead_times_variability,
        "Manufacturing Lead Time"::INTEGER                  AS manufacturing_lead_time,
        "Production Volumes"::INTEGER                       AS production_volumes,

        -- Cost measures
        ROUND(CAST("Manufacturing Costs" AS NUMERIC), 2)            AS manufacturing_costs,
        ROUND(CAST("Shipping Costs" AS NUMERIC), 2)                 AS shipping_costs,
        ROUND(CAST("Total Logistics Cost" AS NUMERIC), 2)           AS total_logistics_cost,

        -- Quality measures
        ROUND(CAST("Defect Rates" AS NUMERIC), 4)                   AS defect_rates,
        TRIM(UPPER("Inspection Results"))                   AS inspection_results,

        -- Logistics measures
        "Shipping Times"::INTEGER                           AS shipping_times,
        TRIM(LOWER("Transportation Modes"))                 AS transportation_modes,
        TRIM(LOWER("Routes"))                               AS routes,

        -- Derived flags
        CASE
            WHEN "Stock Levels" = 0  THEN 'Stockout'
            WHEN "Stock Levels" < 20 THEN 'Critical'
            WHEN "Stock Levels" < 50 THEN 'Low'
            ELSE 'Healthy'
        END AS stock_status_flag,

        CASE
            WHEN "Defect Rates" >= 4.0 THEN 'High Risk'
            WHEN "Defect Rates" >= 2.0 THEN 'Medium Risk'
            ELSE 'Low Risk'
        END AS defect_risk_flag,

        CASE
            WHEN "Revenue Generated" > 0
                AND "Manufacturing Costs" > 0
            THEN ROUND(
                    (CAST("Revenue Generated" AS NUMERIC) - CAST("Manufacturing Costs" AS NUMERIC) - CAST("Shipping Costs" AS NUMERIC))
                    / NULLIF(CAST("Revenue Generated" AS NUMERIC), 0) * 100,
                2)
            ELSE NULL
        END                                                 AS gross_margin_pct

    FROM source
    WHERE
        "Transaction ID"    IS NOT NULL
        AND "Transaction Date" IS NOT NULL
        AND "SKU"           IS NOT NULL
        AND "Supplier Name" IS NOT NULL
)
SELECT *
FROM transactions_cleaned;


-- ── STAGING.stg_suppliers ────────────────────────────────────
CREATE OR REPLACE VIEW staging.stg_suppliers AS
WITH source AS (
    SELECT *
    FROM landing.supply_chain_final
),
suppliers_ranked AS (
    SELECT
        TRIM(LOWER("Supplier Name"))    AS supplier_name,
        TRIM("Location")                AS location,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(LOWER("Supplier Name"))
            ORDER BY "Supplier Name"
        )                               AS rn
    FROM source
    WHERE "Supplier Name" IS NOT NULL
),
suppliers_deduped AS (
    SELECT
        supplier_name,
        location
    FROM suppliers_ranked
    WHERE rn = 1
),
suppliers_enriched AS (
    SELECT
        supplier_name,
        location,
        CASE
            WHEN LOWER(location) IN ('mumbai','delhi','bangalore',
                                     'chennai','kolkata')
            THEN 'India'
            ELSE 'Unknown'
        END                             AS supplier_country
    FROM suppliers_deduped
)
SELECT *
FROM suppliers_enriched;


-- ── STAGING.stg_products ─────────────────────────────────────
CREATE OR REPLACE VIEW staging.stg_products AS
WITH source AS (
    SELECT *
    FROM landing.supply_chain_final
),
products_extracted AS (
    SELECT DISTINCT
        TRIM(LOWER("SKU"))              AS sku,
        TRIM(LOWER("Product Type"))     AS product_type
    FROM source
    WHERE "SKU" IS NOT NULL
),
products_enriched AS (
    SELECT
        sku,
        product_type,
        CAST(REPLACE(UPPER(sku), 'SKU', '') AS INTEGER) AS sku_number
    FROM products_extracted
)
SELECT *
FROM products_enriched
ORDER BY sku_number;


-- ── STAGING.stg_logistics ────────────────────────────────────
CREATE OR REPLACE VIEW staging.stg_logistics AS
WITH source AS (
    SELECT *
    FROM landing.supply_chain_final
),
logistics_ranked AS (
    SELECT
        TRIM(LOWER("Shipping Carriers"))    AS shipping_carriers,
        TRIM(LOWER("Transportation Modes")) AS transportation_modes,
        TRIM(LOWER("Routes"))               AS routes,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(LOWER("Shipping Carriers"))
            ORDER BY "Shipping Carriers"
        )                                   AS rn
    FROM source
    WHERE "Shipping Carriers" IS NOT NULL
),
logistics_deduped AS (
    SELECT
        shipping_carriers,
        transportation_modes,
        routes
    FROM logistics_ranked
    WHERE rn = 1
),
logistics_enriched AS (
    SELECT
        shipping_carriers,
        transportation_modes,
        routes,
        CASE transportation_modes
            WHEN 'air'  THEN 'Premium'
            WHEN 'road' THEN 'Standard'
            WHEN 'sea'  THEN 'Economy'
            ELSE             'Unknown'
        END                                 AS cost_tier
    FROM logistics_deduped
)
SELECT *
FROM logistics_enriched;


-- ============================================================
-- LAYER 3 — MARTS
-- Final analytical views with surrogate keys and FK joins.
-- ============================================================

-- ── MARTS.dim_supplier ───────────────────────────────────────
CREATE OR REPLACE VIEW marts.dim_supplier AS
SELECT
    MD5(supplier_name)          AS supplier_pk,
    supplier_name,
    location,
    supplier_country
FROM staging.stg_suppliers;


-- ── MARTS.dim_product ────────────────────────────────────────
CREATE OR REPLACE VIEW marts.dim_product AS
SELECT
    MD5(sku)                    AS product_pk,
    sku,
    product_type,
    sku_number
FROM staging.stg_products;


-- ── MARTS.dim_carrier ────────────────────────────────────────
CREATE OR REPLACE VIEW marts.dim_carrier AS
SELECT
    MD5(shipping_carriers)      AS carrier_pk,
    shipping_carriers,
    transportation_modes,
    routes,
    cost_tier
FROM staging.stg_logistics;


-- ── MARTS.dim_date ───────────────────────────────────────────
CREATE OR REPLACE VIEW marts.dim_date AS
WITH date_spine AS (
    SELECT DISTINCT
        "Transaction Date"::DATE            AS date
    FROM landing.supply_chain_final
),
date_enriched AS (
    SELECT
        TO_CHAR(date, 'YYYYMMDD')::INTEGER  AS date_id,
        date,
        EXTRACT(YEAR    FROM date)::INTEGER AS year,
        EXTRACT(MONTH   FROM date)::INTEGER AS month,
        EXTRACT(QUARTER FROM date)::INTEGER AS quarter,
        EXTRACT(DOW     FROM date)::INTEGER AS day_of_week,
        TO_CHAR(date, 'Month')              AS month_name,
        TO_CHAR(date, 'Day')                AS day_name,
        CASE
            WHEN EXTRACT(MONTH FROM date) IN (12,1,2)  THEN 'Winter'
            WHEN EXTRACT(MONTH FROM date) IN (3,4,5)   THEN 'Spring'
            WHEN EXTRACT(MONTH FROM date) IN (6,7,8)   THEN 'Monsoon'
            ELSE                                             'Autumn'
        END                                 AS season,
        CASE
            WHEN EXTRACT(DOW FROM date) IN (0,6)
            THEN TRUE ELSE FALSE
        END                                 AS is_weekend
    FROM date_spine
)
SELECT *
FROM date_enriched;


-- ── MARTS.fact_transactions ──────────────────────────────────
-- Kimball-compliant fact view: foreign keys + measures only.
-- Descriptive attributes (product_type, supplier_name, season etc.)
-- are resolved by joining to the relevant dimension view at query time.
CREATE OR REPLACE VIEW marts.fact_transactions AS
WITH transactions AS (
    SELECT *
    FROM staging.stg_transactions
),
suppliers AS (
    SELECT *
    FROM marts.dim_supplier
),
products AS (
    SELECT *
    FROM marts.dim_product
),
carriers AS (
    SELECT *
    FROM marts.dim_carrier
),
dates AS (
    SELECT *
    FROM marts.dim_date
),
fact_joined AS (
    SELECT
        -- Surrogate keys (FK references to dimension tables)
        t.transaction_id                        AS transaction_pk,
        s.supplier_pk                           AS supplier_fk,
        p.product_pk                            AS product_fk,
        c.carrier_pk                            AS carrier_fk,
        d.date_id                               AS date_fk,

        -- Degenerate dimensions (low-cardinality identifiers on the fact)
        t.transaction_date,

        -- Inventory measures
        t.price,
        t.availability,
        t.number_of_products_sold,
        t.revenue_generated,
        t.stock_levels,
        t.order_quantities,
        t.stock_status_flag,

        -- Procurement measures
        t.lead_time,
        t.lead_times_variability,
        t.manufacturing_lead_time,
        t.production_volumes,

        -- Cost measures
        t.manufacturing_costs,
        t.shipping_costs,
        t.total_logistics_cost,

        -- Quality measures
        t.defect_rates,
        t.inspection_results,
        t.defect_risk_flag,

        -- Logistics measures
        t.shipping_times

    FROM transactions t
    LEFT JOIN suppliers s
        ON t.supplier_name      = s.supplier_name
    LEFT JOIN products p
        ON t.sku                = p.sku
    LEFT JOIN carriers c
        ON t.shipping_carriers  = c.shipping_carriers
    LEFT JOIN dates d
        ON t.transaction_date   = d.date
)
SELECT *
FROM fact_joined;


-- ============================================================
-- VERIFICATION QUERIES
-- ============================================================

SELECT 'landing.supply_chain_final'  AS layer, COUNT(*) AS rows FROM landing.supply_chain_final
UNION ALL
SELECT 'staging.stg_transactions',            COUNT(*)          FROM staging.stg_transactions
UNION ALL
SELECT 'staging.stg_suppliers',               COUNT(*)          FROM staging.stg_suppliers
UNION ALL
SELECT 'staging.stg_products',                COUNT(*)          FROM staging.stg_products
UNION ALL
SELECT 'staging.stg_logistics',               COUNT(*)          FROM staging.stg_logistics
UNION ALL
SELECT 'marts.dim_supplier',                  COUNT(*)          FROM marts.dim_supplier
UNION ALL
SELECT 'marts.dim_product',                   COUNT(*)          FROM marts.dim_product
UNION ALL
SELECT 'marts.dim_carrier',                   COUNT(*)          FROM marts.dim_carrier
UNION ALL
SELECT 'marts.dim_date',                      COUNT(*)          FROM marts.dim_date
UNION ALL
SELECT 'marts.fact_transactions',             COUNT(*)          FROM marts.fact_transactions;

-- Check no orphan FK records
SELECT
    SUM(CASE WHEN supplier_fk IS NULL THEN 1 ELSE 0 END) AS null_supplier_fk,
    SUM(CASE WHEN product_fk  IS NULL THEN 1 ELSE 0 END) AS null_product_fk,
    SUM(CASE WHEN carrier_fk  IS NULL THEN 1 ELSE 0 END) AS null_carrier_fk,
    SUM(CASE WHEN date_fk     IS NULL THEN 1 ELSE 0 END) AS null_date_fk
FROM marts.fact_transactions;

-- Preview fact view
SELECT *
FROM marts.fact_transactions
LIMIT 5;
