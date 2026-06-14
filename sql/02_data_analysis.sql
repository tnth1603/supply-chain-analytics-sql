-- ============================================================
-- SUPPLY CHAIN ANALYTICS PROJECT
-- Script: 02_data_analysis.sql
-- Description: Business analysis across 3 modules
--              All queries join fact_transactions to dimension
--              views following Kimball star schema principles
-- Database: PostgreSQL 15
-- Author: Tuan Thanh Thinh
-- ============================================================


-- ============================================================
-- MODULE 1 — SUPPLIER PERFORMANCE & PROCUREMENT
-- ============================================================

-- ------------------------------------------------------------
-- BQ1: Which suppliers have the best and worst on-time delivery rates?
-- Techniques: GROUP BY, AVG, CASE, RANK() window function
-- ------------------------------------------------------------
SELECT
    ds.supplier_name,
    ds.location,
    COUNT(*)                                                            AS total_orders,
    ROUND(CAST(AVG(ft.lead_time) AS NUMERIC), 1)                       AS avg_actual_lead_time,
    ROUND(CAST(AVG(ft.manufacturing_lead_time) AS NUMERIC), 1)         AS avg_expected_lead_time,
    ROUND(CAST(AVG(ft.lead_time - ft.manufacturing_lead_time) AS NUMERIC), 1) AS avg_delay_days,
    ROUND(
        SUM(CASE WHEN ft.lead_time <= ft.manufacturing_lead_time
            THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    )                                                                   AS on_time_rate_pct,
    RANK() OVER (
        ORDER BY AVG(ft.lead_time - ft.manufacturing_lead_time) ASC
    )                                                                   AS performance_rank
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
GROUP BY ds.supplier_name, ds.location
ORDER BY avg_delay_days ASC;


-- ------------------------------------------------------------
-- BQ2: Which suppliers pose the highest quality risk?
-- Techniques: SUM CASE, AVG, CASE risk classification
-- ------------------------------------------------------------
SELECT
    ds.supplier_name,
    ds.location,
    COUNT(*)                                                            AS total_orders,
    ROUND(CAST(AVG(ft.defect_rates) AS NUMERIC), 4)                    AS avg_defect_rate,
    ROUND(CAST(MAX(ft.defect_rates) AS NUMERIC), 4)                    AS max_defect_rate,
    SUM(CASE WHEN ft.inspection_results = 'FAIL'
        THEN 1 ELSE 0 END)                                             AS total_failed_inspections,
    ROUND(
        SUM(CASE WHEN ft.inspection_results = 'FAIL'
            THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    )                                                                   AS fail_rate_pct,
    CASE
        WHEN AVG(ft.defect_rates) >= 4.0 THEN 'High Risk — Immediate Review'
        WHEN AVG(ft.defect_rates) >= 2.0 THEN 'Medium Risk — Monitor Closely'
        ELSE                                  'Low Risk — Reliable'
    END                                                                 AS risk_classification
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
GROUP BY ds.supplier_name, ds.location
ORDER BY avg_defect_rate DESC;

-- ------------------------------------------------------------
-- BQ3: Are high-volume suppliers more or less reliable?
-- Techniques: NTILE() volume tier, multi-metric aggregation
-- ------------------------------------------------------------
SELECT
    ds.supplier_name,
    ds.location,
    SUM(ft.order_quantities)                                            AS total_units_ordered,
    COUNT(*)                                                            AS total_transactions,
    ROUND(CAST(AVG(ft.lead_time) AS NUMERIC), 1)                       AS avg_lead_time,
    ROUND(CAST(AVG(ft.defect_rates) AS NUMERIC), 4)                    AS avg_defect_rate,
    NTILE(3) OVER (
        ORDER BY SUM(ft.order_quantities) DESC
    )                                                                   AS volume_tier
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
GROUP BY ds.supplier_name, ds.location
ORDER BY total_units_ordered DESC;


-- ------------------------------------------------------------
-- BQ4: Has supplier lead time improved or deteriorated over time?
-- Techniques: CTE pre-aggregation, LAG(), month-over-month trend
-- Note: AVG is computed once in the CTE; LAG() references the
--       pre-computed alias in the outer SELECT, avoiding fragile
--       ROUND(LAG(CAST(AVG(...)))) nesting and double evaluation.
-- ------------------------------------------------------------
WITH monthly_avg AS (
    SELECT
        ds.supplier_name,
        ds.location,
        dd.year,
        dd.month,
        dd.month_name,
        ROUND(CAST(AVG(ft.lead_time) AS NUMERIC), 1)                   AS avg_lead_time
    FROM marts.fact_transactions ft
    LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
    LEFT JOIN marts.dim_date     dd ON ft.date_fk     = dd.date_id
    GROUP BY ds.supplier_name, ds.location, dd.year, dd.month, dd.month_name
)
SELECT
    supplier_name,
    location,
    year,
    month,
    month_name,
    avg_lead_time,
    ROUND(
        avg_lead_time
        - LAG(avg_lead_time) OVER (
            PARTITION BY supplier_name, location
            ORDER BY year, month
        ), 1
    )                                                                   AS mom_change
FROM monthly_avg
ORDER BY supplier_name, location, year, month;


-- ============================================================
-- MODULE 2 — INVENTORY MANAGEMENT
-- ============================================================

-- ------------------------------------------------------------
-- BQ1: Which SKUs need urgent restocking at a 95% service level, 
-- 		accounting for demand and lead time variability?

-- Domain:
--   In practice, both demand and lead times vary. A simple ROP
--   (avg_demand × avg_lead_time) ignores this variability and
--   consistently leads to stockouts. The statistically correct
--   formula accounts for variance in both dimensions:
--
--   Safety Stock = Z × SQRT( (avg_lead_time × VARIANCE(demand))
--                           + (avg_demand²  × VARIANCE(lead_time)) )
--
--   Where Z = 1.65 (95% service level)
--   ROP = (avg_demand × avg_lead_time) + safety_stock
--
--   avg_demand    = AVG(number_of_products_sold) per SKU
--   avg_lead_time = AVG(lead_time) per SKU
--   VARIANCE()    = STDDEV()² — both demand and lead time variability
--                  contribute to stockout risk
--
-- Interpretation of reorder_action:
--   URGENT        — current avg stock is at or below zero (stockout)
--   WARNING       — avg stock is below the statistically safe ROP
--   OK            — sufficient buffer exists at current service level
--
-- Techniques: STDDEV, SQRT compound safety stock formula, CASE
-- ------------------------------------------------------------
WITH sku_stats AS (
    SELECT
        dp.sku,
        dp.product_type,
        ds.supplier_name,
        ds.location,
        COUNT(*)                                                        AS total_transactions,
        ROUND(CAST(AVG(ft.stock_levels)              AS NUMERIC), 1)   AS avg_stock_level,
        ROUND(CAST(AVG(ft.number_of_products_sold)   AS NUMERIC), 2)   AS avg_demand,
        ROUND(CAST(STDDEV(ft.number_of_products_sold) AS NUMERIC), 2)  AS stddev_demand,
        ROUND(CAST(AVG(ft.lead_time)                 AS NUMERIC), 2)   AS avg_lead_time,
        ROUND(CAST(STDDEV(ft.lead_time)              AS NUMERIC), 2)   AS stddev_lead_time
    FROM marts.fact_transactions ft
    LEFT JOIN marts.dim_product  dp ON ft.product_fk  = dp.product_pk
    LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
    GROUP BY dp.sku, dp.product_type, ds.supplier_name, ds.location
)
SELECT
    sku,
    product_type,
    supplier_name,
    location,
    total_transactions,
    avg_stock_level,
    avg_demand,
    stddev_demand,
    avg_lead_time,
    stddev_lead_time,
    -- Statistical safety stock formula (APICS standard):
    -- Z × SQRT( avg_LT × VAR(demand) + avg_demand² × VAR(LT) )
    ROUND(
        1.65 * SQRT(
            (avg_lead_time  * POWER(COALESCE(stddev_demand,    0), 2))
          + (POWER(avg_demand, 2) * POWER(COALESCE(stddev_lead_time, 0), 2))
        ), 0
    )                                                                   AS safety_stock,
    -- ROP = avg pipeline demand + safety stock
    ROUND(
        (avg_demand * avg_lead_time)
        + 1.65 * SQRT(
            (avg_lead_time  * POWER(COALESCE(stddev_demand,    0), 2))
          + (POWER(avg_demand, 2) * POWER(COALESCE(stddev_lead_time, 0), 2))
        ), 0
    )                                                                   AS reorder_point,
    CASE
        WHEN avg_stock_level <= 0
            THEN 'URGENT — Stockout'
        WHEN avg_stock_level < ROUND(
            (avg_demand * avg_lead_time)
            + 1.65 * SQRT(
                (avg_lead_time  * POWER(COALESCE(stddev_demand,    0), 2))
              + (POWER(avg_demand, 2) * POWER(COALESCE(stddev_lead_time, 0), 2))
            ), 0)
            THEN 'WARNING — Below ROP'
        ELSE 'OK — Sufficient Stock'
    END                                                                 AS reorder_action
FROM sku_stats
ORDER BY reorder_point DESC;


-- ------------------------------------------------------------
-- BQ2: How efficiently does each product category turn over 
--		inventory per quarter, measured by unit ITR, value ITR, and DSI?

--
-- Domain:
--   ITR and DSI are the two primary inventory efficiency metrics
--   used in supply chain reporting. They must be calculated at
--   the aggregate level — not averaged row-by-row — to be valid.
--
--   Unit-based ITR:
--     Total units sold in the period / avg stock level in the period
--     Measures how many times physical stock was replenished.
--
--   Value-based ITR (financial):
--     Total COGS in the period / avg inventory value in the period
--     Avg inventory value = avg_stock_level × avg unit cost (mfg + shipping)
--     Reflects the financial efficiency of capital tied up in stock.
--     Standard metric for CFO/finance reporting.
--
--   DSI (Days Sales of Inventory):
--     90 / unit_itr  (number of days in a quarter)
--     How many days of sales the current stock can cover.
--     Lower DSI = leaner inventory. Higher DSI = overstock risk.
--
--   Both ratios are calculated per product_type × quarter so
--   trends are visible over the 8-quarter dataset window.
--
-- Techniques: CTE aggregation, RANK(), LAG() QoQ trend,
--             dual ITR (unit + value), DSI derivation
-- ------------------------------------------------------------
WITH period_agg AS (
    -- Aggregate all measures to product_type × year × quarter first.
    -- Ratio calculation only happens in the outer SELECT.
    SELECT
        dp.product_type,
        dd.year,
        dd.quarter,
        SUM(ft.number_of_products_sold)                                AS total_units_sold,
        ROUND(CAST(AVG(ft.stock_levels) AS NUMERIC), 2)                AS avg_stock_level,
        -- COGS: mfg_costs is per-unit (multiply by units sold);
        --       shipping_costs is a per-shipment flat fee (add once, no multiplication)
        ROUND(
            CAST(SUM(ft.number_of_products_sold * ft.manufacturing_costs
                + ft.shipping_costs) AS NUMERIC), 2
        )                                                              AS total_cogs,
        -- Avg inventory value: avg stock × avg unit mfg cost (shipping excluded —
        --   it is a transaction cost, not embedded in inventory value)
        ROUND(
            CAST(AVG(ft.stock_levels) AS NUMERIC)
            * CAST(AVG(ft.manufacturing_costs) AS NUMERIC), 2
        )                                                              AS avg_inventory_value
    FROM marts.fact_transactions ft
    LEFT JOIN marts.dim_product dp ON ft.product_fk = dp.product_pk
    LEFT JOIN marts.dim_date    dd ON ft.date_fk    = dd.date_id
    GROUP BY dp.product_type, dd.year, dd.quarter
),
itr_calc AS (
    SELECT
        product_type,
        year,
        quarter,
        total_units_sold,
        avg_stock_level,
        total_cogs,
        avg_inventory_value,
        -- Unit-based ITR
        ROUND(
            CAST(total_units_sold AS NUMERIC)
            / NULLIF(avg_stock_level, 0), 2
        )                                                              AS unit_itr,
        -- Value-based ITR (financial)
        ROUND(
            total_cogs
            / NULLIF(avg_inventory_value, 0), 2
        )                                                              AS value_itr
    FROM period_agg
)
SELECT
    product_type,
    year,
    quarter,
    total_units_sold,
    avg_stock_level,
    total_cogs,
    avg_inventory_value,
    unit_itr,
    -- DSI = days in quarter / unit_itr
    ROUND(90.0 / NULLIF(unit_itr, 0), 1)                              AS dsi_days,
    value_itr,
    -- QoQ change in unit ITR per product type
    ROUND(
        unit_itr
        - LAG(unit_itr) OVER (
            PARTITION BY product_type
            ORDER BY year, quarter
        ), 2
    )                                                                  AS unit_itr_qoq_change,
    -- Rank product types by unit ITR within each quarter
    RANK() OVER (
        PARTITION BY year, quarter
        ORDER BY unit_itr DESC
    )                                                                  AS itr_rank_in_quarter,
    CASE
        WHEN unit_itr >= 10 THEN 'Fast Moving'
        WHEN unit_itr >=  5 THEN 'Normal Turnover'
        ELSE                     'Slow Moving — Review Stock'
    END                                                                AS velocity_flag
FROM itr_calc
ORDER BY product_type, year, quarter;


-- ============================================================
-- MODULE 3 — COST TRACKING & MARGIN ANALYSIS
-- ============================================================

-- ------------------------------------------------------------
-- BQ1: Which product types generate the highest gross margins?
-- Domain:
--   manufacturing_costs = per-unit field (confirmed by data inspection)
--   shipping_costs      = per-shipment flat fee (does not scale with units sold)
--   COGS = (number_of_products_sold × manufacturing_costs) + shipping_costs
--   Gross Margin % = (Revenue - COGS) / Revenue × 100
--   Net Logistics Margin %: reported separately below as it includes the
--   per-shipment shipping cost on top of unit manufacturing cost.
-- Techniques: SUM, COGS-based margin calculation, RANK()
-- ------------------------------------------------------------
SELECT
    dp.product_type,
    COUNT(*)                                                            AS total_transactions,
    ROUND(CAST(SUM(ft.revenue_generated) AS NUMERIC), 2)               AS total_revenue,
    ROUND(
        CAST(SUM(ft.number_of_products_sold * ft.manufacturing_costs
            + ft.shipping_costs) AS NUMERIC), 2
    )                                                                   AS total_cogs,
    ROUND(
        CAST(SUM(ft.revenue_generated) AS NUMERIC)
        - CAST(SUM(ft.number_of_products_sold * ft.manufacturing_costs
            + ft.shipping_costs) AS NUMERIC), 2
    )                                                                   AS gross_profit,
    ROUND(
        (CAST(SUM(ft.revenue_generated) AS NUMERIC)
            - CAST(SUM(ft.number_of_products_sold * ft.manufacturing_costs
                + ft.shipping_costs) AS NUMERIC))
        / NULLIF(CAST(SUM(ft.revenue_generated) AS NUMERIC), 0) * 100, 1
    )                                                                   AS gross_margin_pct,
    RANK() OVER (
        ORDER BY
            (CAST(SUM(ft.revenue_generated) AS NUMERIC)
                - CAST(SUM(ft.number_of_products_sold * ft.manufacturing_costs
                    + ft.shipping_costs) AS NUMERIC))
            / NULLIF(CAST(SUM(ft.revenue_generated) AS NUMERIC), 0) DESC
    )                                                                   AS margin_rank
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_product dp ON ft.product_fk = dp.product_pk
GROUP BY dp.product_type
ORDER BY gross_margin_pct DESC;


-- ------------------------------------------------------------
-- BQ2: What proportion of total cost is manufacturing
--      vs shipping per product type?
-- Note: manufacturing_costs is per-unit; shipping_costs is per-shipment flat fee.
--       AVG(manufacturing_costs) = avg unit cost per transaction — correct for
--       cost structure analysis. shipping_costs averaged across transactions
--       gives avg per-shipment fee, which is also valid here.
--       pct_of_total_spend weights by actual COGS incurred per category.
-- Techniques: Percentage share, SUM OVER() total spend
-- ------------------------------------------------------------
SELECT
    dp.product_type,
    ROUND(CAST(AVG(ft.manufacturing_costs) AS NUMERIC), 2)             AS avg_mfg_cost_per_unit,
    ROUND(CAST(AVG(ft.shipping_costs) AS NUMERIC), 2)                  AS avg_shipping_cost_per_shipment,
    ROUND(
        CAST(AVG(ft.manufacturing_costs) AS NUMERIC)
        + CAST(AVG(ft.shipping_costs) AS NUMERIC), 2
    )                                                                   AS avg_total_cost_per_txn,
    ROUND(
        CAST(AVG(ft.manufacturing_costs) AS NUMERIC) * 100.0
        / NULLIF(
            CAST(AVG(ft.manufacturing_costs) AS NUMERIC)
            + CAST(AVG(ft.shipping_costs) AS NUMERIC), 0
        ), 1
    )                                                                   AS mfg_cost_share_pct,
    ROUND(
        CAST(AVG(ft.shipping_costs) AS NUMERIC) * 100.0
        / NULLIF(
            CAST(AVG(ft.manufacturing_costs) AS NUMERIC)
            + CAST(AVG(ft.shipping_costs) AS NUMERIC), 0
        ), 1
    )                                                                   AS shipping_cost_share_pct,
    -- Total COGS: units_sold × mfg_cost (per-unit) + shipping_cost (flat per txn)
    ROUND(
        SUM(CAST(ft.number_of_products_sold AS NUMERIC)
            * CAST(ft.manufacturing_costs AS NUMERIC)
            + CAST(ft.shipping_costs AS NUMERIC)) * 100.0
        / SUM(SUM(CAST(ft.number_of_products_sold AS NUMERIC)
            * CAST(ft.manufacturing_costs AS NUMERIC)
            + CAST(ft.shipping_costs AS NUMERIC))) OVER (), 1
    )                                                                   AS pct_of_total_spend
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_product dp ON ft.product_fk = dp.product_pk
GROUP BY dp.product_type
ORDER BY avg_total_cost_per_txn DESC;


-- ------------------------------------------------------------
-- BQ3: Are manufacturing costs increasing over 2 years?
-- Note: AVG(manufacturing_costs) tracks average unit cost trend
--       over time per product type — correct for cost inflation
--       analysis independent of volume changes.
-- Techniques: LAG(), quarter-over-quarter cost inflation trend
-- ------------------------------------------------------------
SELECT
    dd.year,
    dd.quarter,
    dp.product_type,
    ROUND(CAST(AVG(ft.manufacturing_costs) AS NUMERIC), 2)             AS avg_mfg_cost,
    ROUND(CAST(AVG(ft.shipping_costs) AS NUMERIC), 2)                  AS avg_shipping_cost,
    ROUND(
        CAST(AVG(ft.manufacturing_costs) AS NUMERIC)
        - LAG(CAST(AVG(ft.manufacturing_costs) AS NUMERIC))
            OVER (
                PARTITION BY dp.product_type
                ORDER BY dd.year, dd.quarter
            ), 2
    )                                                                   AS qoq_cost_change,
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
    )                                                                   AS qoq_change_pct
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_product dp ON ft.product_fk = dp.product_pk
LEFT JOIN marts.dim_date    dd ON ft.date_fk    = dd.date_id
GROUP BY dd.year, dd.quarter, dp.product_type
ORDER BY dp.product_type, dd.year, dd.quarter;


-- ------------------------------------------------------------
-- BQ4: Which suppliers deliver the best revenue-to-cost ratio?
-- Domain:
--   COGS = (number_of_products_sold × manufacturing_costs) + shipping_costs
--   manufacturing_costs is per-unit; shipping_costs is per-shipment flat fee.
--   Revenue-to-Cost Ratio = total_revenue / total_cogs
--   Net Logistics Margin % = (Revenue - COGS) / Revenue × 100
-- Techniques: Ratio calculation, efficiency ranking, RANK()
-- ------------------------------------------------------------
SELECT
    ds.supplier_name,
    ds.location,
    ROUND(CAST(SUM(ft.revenue_generated) AS NUMERIC), 2)               AS total_revenue,
    ROUND(
        CAST(SUM(ft.number_of_products_sold * ft.manufacturing_costs
            + ft.shipping_costs) AS NUMERIC), 2
    )                                                                   AS total_cogs,
    ROUND(
        CAST(SUM(ft.revenue_generated) AS NUMERIC)
        / NULLIF(
            CAST(SUM(ft.number_of_products_sold * ft.manufacturing_costs
                + ft.shipping_costs) AS NUMERIC), 0
        ), 2
    )                                                                   AS revenue_to_cost_ratio,
    ROUND(
        (CAST(SUM(ft.revenue_generated) AS NUMERIC)
            - CAST(SUM(ft.number_of_products_sold * ft.manufacturing_costs
                + ft.shipping_costs) AS NUMERIC))
        / NULLIF(CAST(SUM(ft.revenue_generated) AS NUMERIC), 0) * 100, 1
    )                                                                   AS net_logistics_margin_pct,
    RANK() OVER (
        ORDER BY
            CAST(SUM(ft.revenue_generated) AS NUMERIC)
            / NULLIF(
                CAST(SUM(ft.number_of_products_sold * ft.manufacturing_costs
                    + ft.shipping_costs) AS NUMERIC), 0
            ) DESC
    )                                                                   AS efficiency_rank
FROM marts.fact_transactions ft
LEFT JOIN marts.dim_supplier ds ON ft.supplier_fk = ds.supplier_pk
GROUP BY ds.supplier_name, ds.location
ORDER BY revenue_to_cost_ratio DESC;