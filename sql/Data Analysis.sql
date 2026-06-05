-- =====================================================================
-- SUPPLY CHAIN ANALYTICS PROJECT
-- Script: 02_data_analysis.sql
-- Description: Business analysis across 3 modules
--              All queries join fact_transactions to dimension
--              views following Kimball star schema principles
-- Database: PostgreSQL 15
-- Author: Tuan Thanh Thinh

-- =====================================================================
-- MODULE 1 — SUPPLIER PERFORMANCE & PROCUREMENT
-- =====================================================================

-- ---------------------------------------------------------------------
-- BQ1: Which suppliers have the best and worst on-time delivery rates?
-- Techniques: GROUP BY, AVG, CASE, RANK() window function
-- ---------------------------------------------------------------------
SELECT
    ds.supplier_name,
    COUNT(*)                                                AS total_orders,
    ROUND(CAST(AVG(ft.lead_time) AS NUMERIC), 1)           AS avg_actual_lead_time,
    ROUND(CAST(AVG(ft.manufacturing_lead_time) AS NUMERIC), 1) AS avg_expected_lead_time,
    ROUND(CAST(AVG(ft.lead_time - ft.manufacturing_lead_time) AS NUMERIC), 1) AS avg_delay_days,
    ROUND(
        SUM(CASE WHEN ft.lead_time <= ft.manufacturing_lead_time
            THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    )                                                       AS on_time_rate_pct,
    RANK() OVER (
        ORDER BY AVG(ft.lead_time - ft.manufacturing_lead_time) ASC
    )                                                       AS performance_rank
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
GROUP BY ds.supplier_name
ORDER BY avg_delay_days ASC;


-- ------------------------------------------------------------
-- BQ2: Which suppliers pose the highest quality risk?
-- Techniques: SUM CASE, AVG, CASE risk classification
-- ------------------------------------------------------------
SELECT
    ds.supplier_name,
    COUNT(*)                                                AS total_orders,
    ROUND(CAST(AVG(ft.defect_rates) AS NUMERIC), 4)        AS avg_defect_rate,
    ROUND(CAST(MAX(ft.defect_rates) AS NUMERIC), 4)        AS max_defect_rate,
    SUM(CASE WHEN ft.inspection_results = 'FAIL'
        THEN 1 ELSE 0 END)                                 AS total_failed_inspections,
    ROUND(
        SUM(CASE WHEN ft.inspection_results = 'FAIL'
            THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    )                                                       AS fail_rate_pct,
    CASE
        WHEN AVG(ft.defect_rates) >= 4.0 THEN 'High Risk — Immediate Review'
        WHEN AVG(ft.defect_rates) >= 2.0 THEN 'Medium Risk — Monitor Closely'
        ELSE                                  'Low Risk — Reliable'
    END                                                     AS risk_classification
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
GROUP BY ds.supplier_name
ORDER BY avg_defect_rate DESC;


-- ------------------------------------------------------------
-- BQ3: Are high-volume suppliers more or less reliable?
-- Techniques: NTILE() volume tier, multi-metric aggregation
-- ------------------------------------------------------------
SELECT
    ds.supplier_name,
    SUM(ft.order_quantities)                                AS total_units_ordered,
    COUNT(*)                                                AS total_transactions,
    ROUND(CAST(AVG(ft.lead_time) AS NUMERIC), 1)           AS avg_lead_time,
    ROUND(CAST(AVG(ft.defect_rates) AS NUMERIC), 4)        AS avg_defect_rate,
    NTILE(3) OVER (
        ORDER BY SUM(ft.order_quantities) DESC
    )                                                       AS volume_tier
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
GROUP BY ds.supplier_name
ORDER BY total_units_ordered DESC;


-- ------------------------------------------------------------
-- BQ4: Has supplier lead time improved or deteriorated over time?
-- Techniques: LAG(), PARTITION BY, month-over-month trend
-- ------------------------------------------------------------
SELECT
    ds.supplier_name,
    dd.year,
    dd.month,
    dd.month_name,
    ROUND(CAST(AVG(ft.lead_time) AS NUMERIC), 1)           AS avg_lead_time,
    ROUND(
        CAST(AVG(ft.lead_time) AS NUMERIC)
        - LAG(CAST(AVG(ft.lead_time) AS NUMERIC))
            OVER (
                PARTITION BY ds.supplier_name
                ORDER BY dd.year, dd.month
            ), 1
    )                                                       AS mom_change
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
LEFT JOIN marts.dim_date     dd ON ft.date_fk     = dd.date_id
GROUP BY ds.supplier_name, dd.year, dd.month, dd.month_name
ORDER BY ds.supplier_name, dd.year, dd.month;


-- ============================================================
-- MODULE 2 — INVENTORY MANAGEMENT
-- ============================================================

-- ------------------------------------------------------------
-- BQ1: Which SKUs are critically low and need urgent reorder?
-- Domain: Reorder Point = (Avg Daily Sales × Avg Lead Time)
--         + Safety Stock
-- Safety Stock = 1.65 × Avg Daily Sales × STDDEV(Lead Time)
-- 1.65 = Z-score for 95% service level
-- Techniques: STDDEV, COALESCE, reorder point calculation
-- ------------------------------------------------------------
SELECT
    dp.sku,
    dp.product_type,
    ds.supplier_name,
    ROUND(CAST(AVG(ft.stock_levels) AS NUMERIC), 0)        AS avg_stock_level,
    ROUND(CAST(AVG(ft.number_of_products_sold) AS NUMERIC), 1) AS avg_daily_sales,
    ROUND(CAST(AVG(ft.lead_time) AS NUMERIC), 1)           AS avg_lead_time_days,
    ROUND(
        1.65
        * CAST(AVG(ft.number_of_products_sold) AS NUMERIC)
        * COALESCE(CAST(STDDEV(ft.lead_time) AS NUMERIC), 0), 0
    )                                                       AS safety_stock,
    ROUND(
        (CAST(AVG(ft.number_of_products_sold) AS NUMERIC)
            * CAST(AVG(ft.lead_time) AS NUMERIC))
        + (1.65
            * CAST(AVG(ft.number_of_products_sold) AS NUMERIC)
            * COALESCE(CAST(STDDEV(ft.lead_time) AS NUMERIC), 0)), 0
    )                                                       AS reorder_point,
    ft.stock_status_flag,
    CASE
        WHEN AVG(ft.stock_levels) = 0
            THEN 'URGENT — Stockout Now'
        WHEN AVG(ft.stock_levels) < (
            (AVG(ft.number_of_products_sold) * AVG(ft.lead_time))
            + (1.65 * AVG(ft.number_of_products_sold)
                * COALESCE(STDDEV(ft.lead_time), 0))
        )
            THEN 'WARNING — Below Reorder Point'
        ELSE 'OK — Sufficient Stock'
    END                                                     AS reorder_action
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_product  dp ON ft.product_fk  = dp.product_pk
LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
GROUP BY dp.sku, dp.product_type, ds.supplier_name, ft.stock_status_flag
ORDER BY avg_stock_level ASC;


-- ------------------------------------------------------------
-- BQ2: Which product types turn over fastest vs dead stock?
-- Domain: Inventory Turnover = Total Units Sold / Avg Stock
--         Calculated at period level (not row-by-row)
--         per industry standard (Kimball / APICS definition)
-- Techniques: RANK(), period-level ITR aggregation
-- ------------------------------------------------------------
SELECT
    dp.product_type,
    COUNT(DISTINCT dp.sku)                                  AS total_skus,
    SUM(ft.number_of_products_sold)                         AS total_units_sold,
    ROUND(CAST(AVG(ft.stock_levels) AS NUMERIC), 1)        AS avg_stock_level,
    ROUND(
        CAST(SUM(ft.number_of_products_sold) AS NUMERIC)
        / NULLIF(CAST(AVG(ft.stock_levels) AS NUMERIC), 0), 2
    )                                                       AS inventory_turnover_ratio,
    RANK() OVER (
        ORDER BY
            CAST(SUM(ft.number_of_products_sold) AS NUMERIC)
            / NULLIF(CAST(AVG(ft.stock_levels) AS NUMERIC), 0) DESC
    )                                                       AS turnover_rank,
    CASE
        WHEN CAST(SUM(ft.number_of_products_sold) AS NUMERIC)
            / NULLIF(CAST(AVG(ft.stock_levels) AS NUMERIC), 0) >= 5000
            THEN 'Fast Moving'
        WHEN CAST(SUM(ft.number_of_products_sold) AS NUMERIC)
            / NULLIF(CAST(AVG(ft.stock_levels) AS NUMERIC), 0) >= 2000
            THEN 'Medium Moving'
        ELSE 'Slow Moving — Review Stock'
    END                                                     AS movement_category
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_product dp ON ft.product_fk = dp.product_pk
GROUP BY dp.product_type
ORDER BY inventory_turnover_ratio DESC;


-- ------------------------------------------------------------
-- BQ3: Are we overstocked relative to actual sales?
-- Techniques: SUM OVER() cumulative sales, stock-to-sales ratio
-- ------------------------------------------------------------
SELECT
    dp.product_type,
    dd.year,
    dd.quarter,
    SUM(ft.number_of_products_sold)                         AS units_sold,
    ROUND(CAST(AVG(ft.stock_levels) AS NUMERIC), 0)        AS avg_stock,
    ROUND(CAST(AVG(ft.availability) AS NUMERIC), 1)        AS avg_availability_pct,
    ROUND(
        CAST(AVG(ft.stock_levels) AS NUMERIC)
        / NULLIF(CAST(SUM(ft.number_of_products_sold) AS NUMERIC), 0) * 100, 2
    )                                                       AS stock_to_sales_ratio,
    SUM(SUM(ft.number_of_products_sold)) OVER (
        PARTITION BY dp.product_type
        ORDER BY dd.year, dd.quarter
    )                                                       AS cumulative_sales
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_product dp ON ft.product_fk = dp.product_pk
LEFT JOIN marts.dim_date    dd ON ft.date_fk    = dd.date_id
GROUP BY dp.product_type, dd.year, dd.quarter
ORDER BY dp.product_type, dd.year, dd.quarter;


-- ------------------------------------------------------------
-- BQ4: Which seasons drive highest demand and are stock
--      levels aligned?
-- Note: Season uses Northern Hemisphere / Indian mapping:
--       Winter=Dec-Feb, Spring=Mar-May, Monsoon=Jun-Aug,
--       Autumn=Sep-Nov
-- Techniques: EXTRACT, seasonal aggregation, SUM OVER()
-- ------------------------------------------------------------
SELECT
    dp.product_type,
    dd.season,
    SUM(ft.number_of_products_sold)                         AS total_units_sold,
    ROUND(CAST(AVG(ft.stock_levels) AS NUMERIC), 0)        AS avg_stock_level,
    ROUND(CAST(AVG(ft.availability) AS NUMERIC), 1)        AS avg_availability_pct,
    ROUND(
        SUM(ft.number_of_products_sold) * 100.0
        / SUM(SUM(ft.number_of_products_sold)) OVER (
            PARTITION BY dp.product_type
        ), 1
    )                                                       AS season_sales_share_pct
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_product dp ON ft.product_fk = dp.product_pk
LEFT JOIN marts.dim_date    dd ON ft.date_fk    = dd.date_id
GROUP BY dp.product_type, dd.season
ORDER BY dp.product_type, total_units_sold DESC;


-- ============================================================
-- MODULE 3 — COST TRACKING & MARGIN ANALYSIS
-- ============================================================

-- ------------------------------------------------------------
-- BQ1: Which product types generate the highest gross margins?
-- Domain:
--   Gross Margin % = (Revenue - Manufacturing Costs) / Revenue
--   (Manufacturing cost = COGS; excludes shipping which is OpEx)
--   Net Logistics Margin % = (Revenue - Mfg - Shipping) / Revenue
--   (Includes all costs to serve)
-- Techniques: SUM, margin calculation, RANK()
-- ------------------------------------------------------------
SELECT
    dp.product_type,
    COUNT(*)                                                AS total_transactions,
    ROUND(CAST(SUM(ft.revenue_generated) AS NUMERIC), 2)   AS total_revenue,
    ROUND(CAST(SUM(ft.manufacturing_costs) AS NUMERIC), 2) AS total_mfg_cost,
    ROUND(CAST(SUM(ft.shipping_costs) AS NUMERIC), 2)      AS total_shipping_cost,
    ROUND(
        CAST(SUM(ft.revenue_generated) - SUM(ft.manufacturing_costs) AS NUMERIC), 2
    )                                                       AS gross_profit,
    ROUND(
        (CAST(SUM(ft.revenue_generated) AS NUMERIC)
            - CAST(SUM(ft.manufacturing_costs) AS NUMERIC))
        / NULLIF(CAST(SUM(ft.revenue_generated) AS NUMERIC), 0) * 100, 1
    )                                                       AS gross_margin_pct,
    ROUND(
        (CAST(SUM(ft.revenue_generated) AS NUMERIC)
            - CAST(SUM(ft.manufacturing_costs) AS NUMERIC)
            - CAST(SUM(ft.shipping_costs) AS NUMERIC))
        / NULLIF(CAST(SUM(ft.revenue_generated) AS NUMERIC), 0) * 100, 1
    )                                                       AS net_logistics_margin_pct,
    RANK() OVER (
        ORDER BY
            (CAST(SUM(ft.revenue_generated) AS NUMERIC)
                - CAST(SUM(ft.manufacturing_costs) AS NUMERIC))
            / NULLIF(CAST(SUM(ft.revenue_generated) AS NUMERIC), 0) DESC
    )                                                       AS margin_rank
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_product dp ON ft.product_fk = dp.product_pk
GROUP BY dp.product_type
ORDER BY gross_margin_pct DESC;


-- ------------------------------------------------------------
-- BQ2: What proportion of total cost is manufacturing
--      vs shipping per product type?
-- Techniques: Percentage share, SUM OVER() total spend
-- ------------------------------------------------------------
SELECT
    dp.product_type,
    ROUND(CAST(AVG(ft.manufacturing_costs) AS NUMERIC), 2) AS avg_mfg_cost_per_unit,
    ROUND(CAST(AVG(ft.shipping_costs) AS NUMERIC), 2)      AS avg_shipping_cost_per_unit,
    ROUND(
        CAST(AVG(ft.manufacturing_costs) AS NUMERIC)
        + CAST(AVG(ft.shipping_costs) AS NUMERIC), 2
    )                                                       AS avg_total_cost_per_unit,
    ROUND(
        CAST(AVG(ft.manufacturing_costs) AS NUMERIC) * 100.0
        / NULLIF(
            CAST(AVG(ft.manufacturing_costs) AS NUMERIC)
            + CAST(AVG(ft.shipping_costs) AS NUMERIC), 0
        ), 1
    )                                                       AS mfg_cost_share_pct,
    ROUND(
        CAST(AVG(ft.shipping_costs) AS NUMERIC) * 100.0
        / NULLIF(
            CAST(AVG(ft.manufacturing_costs) AS NUMERIC)
            + CAST(AVG(ft.shipping_costs) AS NUMERIC), 0
        ), 1
    )                                                       AS shipping_cost_share_pct,
    ROUND(
        SUM(CAST(ft.manufacturing_costs AS NUMERIC)
            + CAST(ft.shipping_costs AS NUMERIC)) * 100.0
        / SUM(SUM(CAST(ft.manufacturing_costs AS NUMERIC)
            + CAST(ft.shipping_costs AS NUMERIC))) OVER (), 1
    )                                                       AS pct_of_total_spend
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_product dp ON ft.product_fk = dp.product_pk
GROUP BY dp.product_type
ORDER BY avg_total_cost_per_unit DESC;


-- ------------------------------------------------------------
-- BQ3: Are manufacturing costs increasing over 2 years?
-- Techniques: LAG(), quarter-over-quarter cost inflation trend
-- ------------------------------------------------------------
SELECT
    dd.year,
    dd.quarter,
    dp.product_type,
    ROUND(CAST(AVG(ft.manufacturing_costs) AS NUMERIC), 2) AS avg_mfg_cost,
    ROUND(CAST(AVG(ft.shipping_costs) AS NUMERIC), 2)      AS avg_shipping_cost,
    ROUND(
        CAST(AVG(ft.manufacturing_costs) AS NUMERIC)
        - LAG(CAST(AVG(ft.manufacturing_costs) AS NUMERIC))
            OVER (
                PARTITION BY dp.product_type
                ORDER BY dd.year, dd.quarter
            ), 2
    )                                                       AS qoq_cost_change,
    ROUND(
        (CAST(AVG(ft.manufacturing_costs) AS NUMERIC)
            - LAG(CAST(AVG(ft.manufacturing_costs) AS NUMERIC))
                OVER (
                    PARTITION BY dp.product_type
                    ORDER BY dd.year, dd.quarter
                ))
        / NULLIF(
            LAG(CAST(AVG(ft.manufacturing_costs) AS NUMERIC))
                OVER (
                    PARTITION BY dp.product_type
                    ORDER BY dd.year, dd.quarter
                ), 0
        ) * 100, 1
    )                                                       AS qoq_change_pct
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_product dp ON ft.product_fk = dp.product_pk
LEFT JOIN marts.dim_date    dd ON ft.date_fk    = dd.date_id
GROUP BY dd.year, dd.quarter, dp.product_type
ORDER BY dp.product_type, dd.year, dd.quarter;


-- ------------------------------------------------------------
-- BQ4: Which suppliers deliver the best revenue-to-cost ratio?
-- Techniques: Ratio calculation, efficiency ranking, RANK()
-- ------------------------------------------------------------
SELECT
    ds.supplier_name,
    ROUND(CAST(SUM(ft.revenue_generated) AS NUMERIC), 2)   AS total_revenue,
    ROUND(CAST(SUM(ft.manufacturing_costs) AS NUMERIC), 2) AS total_mfg_cost,
    ROUND(CAST(SUM(ft.shipping_costs) AS NUMERIC), 2)      AS total_shipping_cost,
    ROUND(
        CAST(SUM(ft.revenue_generated) AS NUMERIC)
        / NULLIF(
            CAST(SUM(ft.manufacturing_costs) AS NUMERIC)
            + CAST(SUM(ft.shipping_costs) AS NUMERIC), 0
        ), 2
    )                                                       AS revenue_to_cost_ratio,
    ROUND(
        (CAST(SUM(ft.revenue_generated) AS NUMERIC)
            - CAST(SUM(ft.manufacturing_costs) AS NUMERIC)
            - CAST(SUM(ft.shipping_costs) AS NUMERIC))
        / NULLIF(CAST(SUM(ft.revenue_generated) AS NUMERIC), 0) * 100, 1
    )                                                       AS net_logistics_margin_pct,
    RANK() OVER (
        ORDER BY
            CAST(SUM(ft.revenue_generated) AS NUMERIC)
            / NULLIF(
                CAST(SUM(ft.manufacturing_costs) AS NUMERIC)
                + CAST(SUM(ft.shipping_costs) AS NUMERIC), 0
            ) DESC
    )                                                       AS efficiency_rank
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
GROUP BY ds.supplier_name
ORDER BY revenue_to_cost_ratio DESC;
