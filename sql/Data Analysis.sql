
--------------------------------------Supplier Performance & Procurement----------------------------------------

--Business Question 1: Which suppliers consistently deliver within expected lead times and which are chronic underperformers?

SELECT
    ft.supplier_name,
    COUNT(*)                                            AS total_orders,
    ROUND(AVG(ft.lead_time), 1)                        AS avg_actual_lead_time,
    ROUND(AVG(ft.manufacturing_lead_time), 1)          AS avg_expected_lead_time,
    ROUND(AVG(ft.lead_time - ft.manufacturing_lead_time), 1) AS avg_delay_days,
    ROUND(
        SUM(CASE WHEN ft.lead_time <= ft.manufacturing_lead_time
            THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS on_time_rate_pct,
    RANK() OVER (
        ORDER BY AVG(ft.lead_time - ft.manufacturing_lead_time) ASC
    )                                                   AS performance_rank
FROM marts.fact_transactions ft
GROUP BY ft.supplier_name
ORDER BY avg_delay_days ASC;

--Business Question 2: Which suppliers pose the highest quality risk and should be flagged for review?

SELECT
    ft.supplier_name,
    COUNT(*)                                            AS total_orders,
    ROUND(AVG(ft.defect_rates), 4)                     AS avg_defect_rate,
    ROUND(MAX(ft.defect_rates), 4)                     AS max_defect_rate,
    SUM(CASE WHEN ft.inspection_results = 'FAIL'
        THEN 1 ELSE 0 END)                             AS total_failed_inspections,
    ROUND(
        SUM(CASE WHEN ft.inspection_results = 'FAIL'
            THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS fail_rate_pct,
    CASE
        WHEN AVG(ft.defect_rates) >= 4.0 THEN 'High Risk — Immediate Review'
        WHEN AVG(ft.defect_rates) >= 2.0 THEN 'Medium Risk — Monitor Closely'
        ELSE                                  'Low Risk — Reliable'
    END                                                AS risk_classification
FROM marts.fact_transactions ft
GROUP BY ft.supplier_name
ORDER BY avg_defect_rate DESC;



--Business Question 3: Are high-volume suppliers more or less reliable than low-volume ones?
SELECT
    ft.supplier_name,
    SUM(ft.order_quantities)                            AS total_units_ordered,
    COUNT(*)                                            AS total_transactions,
    ROUND(AVG(ft.lead_time), 1)                        AS avg_lead_time,
    ROUND(AVG(ft.defect_rates), 4)                     AS avg_defect_rate,
    NTILE(3) OVER (ORDER BY SUM(ft.order_quantities) DESC) AS volume_tier
FROM marts.fact_transactions ft
GROUP BY ft.supplier_name
ORDER BY total_units_ordered DESC;

--Business Question 4: Has supplier lead time performance improved or deteriorated over the 2-year period?
SELECT
    ft.supplier_name,
    ft.year,
    ft.month,
    ft.month_name,
    ROUND(AVG(ft.lead_time), 1)                         AS avg_lead_time,
    ROUND(AVG(ft.lead_time) - LAG(AVG(ft.lead_time))
        OVER (PARTITION BY ft.supplier_name
              ORDER BY ft.year, ft.month), 1)           AS MoM_change
FROM marts.fact_transactions ft
GROUP BY ft.supplier_name, ft.year, ft.month, ft.month_name
ORDER BY ft.supplier_name, ft.year, ft.month;


--------------------------------------Inventory Management----------------------------------------
--Business Question 1: Which SKUs are at immediate risk of stockout and need urgent replenishment?
SELECT
    ft.sku,
    ft.product_type,
    ft.supplier_name,
    AVG(ft.stock_levels)                                AS avg_stock_level,
    AVG(ft.number_of_products_sold)                     AS avg_daily_sales,
    AVG(ft.lead_time)                                   AS avg_lead_time_days,
    ROUND(AVG(ft.number_of_products_sold)
        * AVG(ft.lead_time), 0)                        AS reorder_point,
    ft.stock_status_flag,
    CASE
        WHEN AVG(ft.stock_levels) = 0
        THEN 'URGENT — Stockout Now'
        WHEN AVG(ft.stock_levels) <
            AVG(ft.number_of_products_sold) * AVG(ft.lead_time)
        THEN 'WARNING — Below Reorder Point'
        ELSE 'OK'
    END                                   AS reorder_action
FROM marts.fact_transactions ft
GROUP BY ft.sku, ft.product_type, ft.supplier_name, ft.stock_status_flag
ORDER BY avg_stock_level ASC;

--Business Question 2: Which product types turn over fastest and which are sitting as dead stock?

SELECT
    product_type,
    COUNT(DISTINCT sku)                                     AS total_skus,
    ROUND(AVG(per_txn_turnover), 2)                         AS inventory_turnover_ratio,
    RANK() OVER (
        ORDER BY AVG(per_txn_turnover) DESC
    )                                                       AS turnover_rank,
    CASE
        WHEN AVG(per_txn_turnover) >= 5  THEN 'Fast Moving'
        WHEN AVG(per_txn_turnover) >= 2  THEN 'Medium Moving'
        ELSE                                  'Slow Moving — Review Stock'
    END                                                     AS movement_category
FROM (
    SELECT
        sku,
        product_type,
        CAST(number_of_products_sold AS NUMERIC)
            / NULLIF(stock_levels, 0)                       AS per_txn_turnover
    FROM marts.fact_transactions
    WHERE stock_levels > 0
) txn_level
GROUP BY product_type
ORDER BY inventory_turnover_ratio DESC;

--Business Question 3: Are we overstocked in any product category relative to actual sales?
SELECT
    ft.product_type,
    ft.year,
    ft.quarter,
    SUM(ft.number_of_products_sold)                     AS units_sold,
    ROUND(AVG(ft.stock_levels), 0)                      AS avg_stock,
    ROUND(AVG(ft.availability), 1)                      AS avg_availability_pct,
    ROUND(
        AVG(ft.stock_levels)::NUMERIC
        / NULLIF(SUM(ft.number_of_products_sold), 0) * 100, 1) AS stock_to_sales_ratio,
    SUM(SUM(ft.number_of_products_sold))
        OVER (PARTITION BY ft.product_type
              ORDER BY ft.year, ft.quarter)             AS cumulative_sales
FROM marts.fact_transactions ft
GROUP BY ft.product_type, ft.year, ft.quarter
ORDER BY ft.product_type, ft.year, ft.quarter;

--Business Question 4: Which seasons drive the highest demand and are stock levels aligned?
SELECT
    ft.product_type,
    ft.season,
    SUM(ft.number_of_products_sold)                     AS total_units_sold,
    ROUND(AVG(ft.stock_levels), 0)                      AS avg_stock_level,
    ROUND(AVG(ft.availability), 1)                      AS avg_availability_pct,
    ROUND(
        SUM(ft.number_of_products_sold) * 100.0
        / SUM(SUM(ft.number_of_products_sold))
            OVER (PARTITION BY ft.product_type), 1)    AS season_sales_share_pct
FROM marts.fact_transactions ft
GROUP BY ft.product_type, ft.season
ORDER BY ft.product_type, total_units_sold DESC;


--------------------------------------Cost Tracking----------------------------------------

--Business Question 1: Which product types generate the highest and lowest gross margins?
SELECT
    ft.product_type,
    COUNT(*)                                            AS total_transactions,
    ROUND(SUM(ft.revenue_generated), 2)                AS total_revenue,
    ROUND(SUM(ft.manufacturing_costs), 2)              AS total_mfg_cost,
    ROUND(SUM(ft.shipping_costs), 2)                   AS total_shipping_cost,
    ROUND(SUM(ft.total_logistics_cost), 2)             AS total_logistics_cost,
    ROUND(
        SUM(ft.revenue_generated)
        - SUM(ft.total_logistics_cost), 2)             AS gross_profit,
    ROUND(
        (SUM(ft.revenue_generated) - SUM(ft.total_logistics_cost))
        / NULLIF(SUM(ft.revenue_generated), 0) * 100, 1) AS gross_margin_pct,
    RANK() OVER (
        ORDER BY
            (SUM(ft.revenue_generated) - SUM(ft.total_logistics_cost))
            / NULLIF(SUM(ft.revenue_generated), 0) DESC
    )                                                   AS margin_rank
FROM marts.fact_transactions ft
GROUP BY ft.product_type
ORDER BY gross_margin_pct DESC;


--Business Question 2: What proportion of total cost is manufacturing vs shipping and how does it vary by product?
SELECT
    ft.product_type,
    ROUND(AVG(ft.manufacturing_costs), 2)               AS avg_mfg_cost_per_unit,
    ROUND(AVG(ft.shipping_costs), 2)                    AS avg_shipping_cost_per_unit,
    ROUND(AVG(ft.manufacturing_costs)
        + AVG(ft.shipping_costs), 2)                    AS avg_total_cost_per_unit,
    ROUND(
        AVG(ft.manufacturing_costs) * 100.0
        / NULLIF(AVG(ft.manufacturing_costs)
            + AVG(ft.shipping_costs), 0), 1)            AS mfg_cost_share_pct,
    ROUND(
        AVG(ft.shipping_costs) * 100.0
        / NULLIF(AVG(ft.manufacturing_costs)
            + AVG(ft.shipping_costs), 0), 1)            AS shipping_cost_share_pct,
    ROUND(
        SUM(ft.manufacturing_costs + ft.shipping_costs) * 100.0
        / SUM(SUM(ft.manufacturing_costs + ft.shipping_costs))
            OVER (), 1)                                 AS pct_of_total_spend
FROM marts.fact_transactions ft
GROUP BY ft.product_type
ORDER BY avg_total_cost_per_unit DESC;

--Business Question 3: Are manufacturing costs increasing over the 2-year period — is cost inflation visible in the data?
select
    ft.year,
    ft.quarter,
    ft.product_type,
    ROUND(AVG(ft.manufacturing_costs), 2)               AS avg_mfg_cost,
    ROUND(AVG(ft.shipping_costs), 2)                    AS avg_shipping_cost,
    ROUND(AVG(ft.manufacturing_costs)
        - LAG(AVG(ft.manufacturing_costs))
            OVER (PARTITION BY ft.product_type
                  ORDER BY ft.year, ft.quarter), 2)     AS qoq_cost_change,
    ROUND(
        (AVG(ft.manufacturing_costs)
        - LAG(AVG(ft.manufacturing_costs))
            OVER (PARTITION BY ft.product_type
                  ORDER BY ft.year, ft.quarter))
        / NULLIF(LAG(AVG(ft.manufacturing_costs))
            OVER (PARTITION BY ft.product_type
                  ORDER BY ft.year, ft.quarter), 0) * 100, 1) AS qoq_change_pct
FROM marts.fact_transactions ft
GROUP BY ft.year, ft.quarter, ft.product_type
ORDER BY ft.product_type, ft.year, ft.quarter;

--Business Question 4: Which suppliers deliver the best revenue-to-cost ratio?
SELECT
    ft.supplier_name,
    ROUND(SUM(ft.revenue_generated), 2)                 AS total_revenue,
    ROUND(SUM(ft.total_logistics_cost), 2)              AS total_cost,
    ROUND(
        SUM(ft.revenue_generated)
        / NULLIF(SUM(ft.total_logistics_cost), 0), 2)  AS revenue_to_cost_ratio,
    ROUND(
        (SUM(ft.revenue_generated) - SUM(ft.total_logistics_cost))
        / NULLIF(SUM(ft.revenue_generated), 0) * 100, 1) AS margin_pct,
    RANK() OVER (
        ORDER BY SUM(ft.revenue_generated)
            / NULLIF(SUM(ft.total_logistics_cost), 0) DESC
    )                                                   AS efficiency_rank
FROM marts.fact_transactions ft
GROUP BY ft.supplier_name
ORDER BY revenue_to_cost_ratio DESC;