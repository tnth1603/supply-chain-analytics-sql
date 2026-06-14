# Supply Chain Analytics — SQL Portfolio Project

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-336791?logo=postgresql&logoColor=white)
![SQL](https://img.shields.io/badge/SQL-Advanced-blue)
![Domain](https://img.shields.io/badge/Domain-Supply%20Chain-green)
![Status](https://img.shields.io/badge/Status-Completed-brightgreen)

## Project Overview

This project simulates the work of a **Supply Chain Data Analyst** tasked with extracting actionable insights from operational transaction data. Using a 10,000-row supply chain dataset spanning 2 years (2022–2023), I designed and implemented a full analytics pipeline — from raw data ingestion through to business-ready analysis — using SQL exclusively.

The project demonstrates both **technical SQL proficiency** and **supply chain domain knowledge** across three critical business functions: supplier performance, inventory management, and cost tracking.

---

## Business Context

A mid-size beauty and personal care company operates across three product categories — haircare, skincare, and cosmetics — sourcing from 5 suppliers across multiple Indian cities. The operations team needed data-driven answers to three core questions:

- Are our suppliers reliable — and which ones are causing delays and quality failures?
- Are we managing inventory efficiently — or are we at risk of stockouts and dead stock?
- Where is our money going — and which products and suppliers deliver the best return?

---

## Dataset

| Attribute | Detail |
|---|---|
| **Source** | Extended from [Amir Motefaker Supply Chain Dataset](https://www.kaggle.com/datasets/amirmotefaker/supply-chain-dataset) (Kaggle) |
| **Original Size** | 100 rows (product/supplier master data) |
| **Extended Size** | 10,000 transaction rows |
| **Period** | January 2022 – December 2023 |
| **Extension Method** | Python — realistic patterns including seasonality, supplier reliability variation, cost inflation, and defect rate simulation |
| **Columns** | 25 columns covering inventory, procurement, cost, quality and logistics |

---

## Tools & Stack

| Layer | Tool |
|---|---|
| Database | PostgreSQL 15 (Docker) |
| SQL Client | DBeaver 26 |
| Dataset Generation | Python (pandas, numpy) |
| Version Control | GitHub |

---

## Project Architecture

```
  Supply Chain Dataset (CSV)
           │
           ▼
┌──────────────────────────────────────────────────────────┐
│                     PostgreSQL 15                        │
│                                                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │   LANDING   │─▶│   STAGING   │─▶│      MARTS      │  │
│  │             │  │             │  │                 │  │
│  │ supply_     │  │ stg_        │  │ dim_supplier    │  │
│  │ chain_final │  │ transactions│  │ dim_product     │  │
│  │             │  │ stg_        │  │ dim_carrier     │  │
│  │ Raw CSV     │  │ suppliers   │  │ dim_date        │  │
│  │ untouched   │  │ stg_        │  │                 │  │
│  │             │  │ products    │  │ fact_           │  │
│  │             │  │ stg_        │  │ transactions    │  │
│  │             │  │ logistics   │  │ (star schema)   │  │
│  └─────────────┘  └─────────────┘  └────────┬────────┘  │
└───────────────────────────────────────────── │ ──────────┘
                                               │
                                               ▼
                                    ┌──────────────────┐
                                    │   DBeaver 26     │
                                    │                  │
                                    │ SQL Analysis     │
                                    │ · Supplier       │
                                    │   Performance    │
                                    │ · Inventory      │
                                    │   Management     │
                                    │ · Cost Tracking  │
                                    └──────────────────┘
```

### Star Schema Design

```
               dim_supplier
                    │
  dim_date ─── fact_transactions ─── dim_product
                    │
               dim_carrier
```

---

## Project Structure

```
supply-chain-sql-analytics/
│
├── README.md
│
├── data/
│   ├── supply_chain_original.csv        ← original 100-row Kaggle dataset
│   ├── supply_chain_10k_final.csv       ← extended 10,000-row dataset
│   └── generate_dataset.py             ← Python script used to generate dataset
│
├── sql/
│   ├── 01_data_cleaning_and_modeling.sql   ← 3-layer schema: landing, staging, marts
│   └── 02_data_analysis.sql               ← all 3 analysis modules and business questions
│
└── results/
    ├── screenshots/
    │   ├── 01_schema_verification.png      ← row counts confirming all layers created correctly
    │   ├── 02_supplier_scorecard.png       ← supplier on-time delivery rate ranking
    │   ├── 03_supplier_defect_risk.png     ← defect rate and risk classification per supplier
    │   ├── 04_safety_stock_rop.png         ← SKU-level safety stock and reorder point analysis
    │   ├── 05_inventory_turnover_dsi.png   ← unit ITR, value ITR and DSI by product type and quarter
    │   ├── 06_gross_margin.png             ← gross margin ranking by product type
    │   ├── 07_cost_breakdown.png           ← manufacturing vs shipping cost share per product
    │   └── 08_cost_trend.png              ← quarterly manufacturing cost inflation over 2 years
    │
    └── key_findings.md                    ← written summary of business insights per module
```

---

## Analysis Modules

### Module 1 — Supplier Performance & Procurement

**Domain relevance:** Supplier reliability is the most critical upstream factor in supply chain performance. Late deliveries and high defect rates cascade into stockouts, production delays and cost overruns.

| # | Business Question | SQL Techniques |
|---|---|---|
| BQ1 | Which suppliers have the best and worst on-time delivery rates? | `GROUP BY`, `AVG`, `CASE`, `RANK()` |
| BQ2 | Which suppliers pose the highest quality risk? | `SUM CASE`, `AVG`, risk classification |
| BQ3 | Are high-volume suppliers more or less reliable? | `NTILE()`, multi-metric aggregation |
| BQ4 | Has supplier lead time improved or deteriorated over time? | CTE pre-aggregation, `LAG()`, `PARTITION BY` |

---

### Module 2 — Inventory Management

**Domain relevance:** Inventory is the most visible output of supply chain decisions. Analysts are expected to quantify stockout risk using statistically sound safety stock models, and measure inventory efficiency through turnover and days-of-inventory metrics — the two core KPIs used in real supply chain reporting.

| # | Business Question | SQL Techniques |
|---|---|---|
| BQ1 | Which SKUs need urgent restocking at a 95% service level, accounting for demand and lead time variability? | CTE, `STDDEV`, `SQRT`, compound safety stock formula, `CASE` |
| BQ2 | How efficiently does each product category turn over inventory per quarter, measured by unit ITR, value ITR, and DSI? | Multi-CTE aggregation, `RANK()`, `LAG()` QoQ trend, dual ITR calculation, DSI derivation |

---

### Module 3 — Cost Tracking & Margin Analysis

**Domain relevance:** Cost visibility is essential for procurement decisions. Analysts must identify which products and suppliers deliver the best margins and where cost inflation is occurring. All margin calculations use a confirmed COGS formula: `(units_sold × manufacturing_costs) + shipping_costs`, where manufacturing cost is a per-unit field and shipping cost is a per-shipment flat fee.

| # | Business Question | SQL Techniques |
|---|---|---|
| BQ1 | Which product types generate the highest gross margins? | `SUM`, COGS-based margin calculation, `RANK()` |
| BQ2 | What proportion of total cost is manufacturing vs shipping per product type? | Percentage share, `SUM OVER()` |
| BQ3 | Are manufacturing costs increasing over the 2-year period? | `LAG()`, quarter-over-quarter trend |
| BQ4 | Which suppliers deliver the best revenue-to-cost ratio? | COGS ratio calculation, efficiency ranking, `RANK()` |

---

## SQL Techniques Demonstrated

| Technique | Description |
|---|---|
| `CTEs` | Multi-step query logic using WITH clauses — used across all modules including nested multi-CTE patterns for ITR/DSI calculation |
| `Window Functions` | `RANK()`, `LAG()`, `NTILE()`, `SUM OVER()`, `PARTITION BY` |
| `Aggregations` | `GROUP BY`, `AVG`, `SUM`, `COUNT DISTINCT`, `STDDEV` |
| `CASE WHEN` | Business logic — risk flags, reorder actions, velocity categories |
| `NULLIF()` | Safe division to prevent divide-by-zero errors |
| `CAST()` | Explicit type conversion for accurate ratio calculations |
| `MD5()` | Composite surrogate key generation for dimension tables |
| `SELECT DISTINCT` | Deduplication in staging layer for suppliers and logistics combinations |
| `SQRT` / `POWER()` | Statistical safety stock formula following APICS standard |
| `EXTRACT()` | Date part extraction for time-series analysis |
| `CREATE OR REPLACE VIEW` | Reusable layer definitions across landing, staging and marts |
| `LEFT JOIN` | FK resolution across fact and dimension tables |
| Schema separation | Three-schema architecture: landing, staging, marts |

---

## Data Modeling Decisions

**Why views instead of tables for staging and marts?**
Views ensure analysis always reflects the latest landing data without requiring re-runs. This mirrors how production data pipelines work in real ERP environments where source data updates continuously.

**Why SELECT DISTINCT instead of ROW_NUMBER() for deduplication?**
The original design used `ROW_NUMBER() PARTITION BY` a single key column, which collapsed multi-attribute entities — for example, a supplier operating across 5 cities was reduced to one arbitrary city row, and a carrier using 3 transport modes was reduced to one mode. `SELECT DISTINCT` on the full combination of meaningful attributes preserves all valid combinations. This corrected a fan-out bug that was inflating `fact_transactions` to 600,000 rows.

**Why composite MD5() surrogate keys?**
Dimension entities in this dataset are identified by multiple attributes — a supplier is uniquely identified by name and city, and a carrier by name, transport mode, and route. Using `MD5(supplier_name || '_' || location)` and `MD5(carrier || '_' || mode || '_' || route)` produces a single stable key per unique combination. Unlike `SERIAL`, MD5 hashes are deterministic across pipeline reruns — critical for incremental loads.

**Why a confirmed COGS formula matters?**
Data inspection revealed that `manufacturing_costs` is stored as a per-unit field while `shipping_costs` is a per-shipment flat fee. This distinction is not documented in the original dataset. Using the wrong formula — treating both as per-unit or both as totals — produces gross margins of either ~99% or negative values. The correct formula `(units_sold × manufacturing_costs) + shipping_costs` is applied consistently across all three margin-related queries in Module 3.

---

## Dataset Constraints

These are known structural limitations of the synthetic dataset that affect how certain metrics are interpreted. They are acknowledged in the SQL comments and factored into analytical conclusions.

**`stock_levels` is a per-transaction snapshot, not a period-opening balance.**
Each row records stock at the moment of that transaction, not the stock level at the start of a period. This means `AVG(stock_levels)` across a quarter reflects an average of point-in-time readings rather than a true average inventory balance. As a result, inventory turnover ratios (ITR) are very high and days sales of inventory (DSI) fall below 1 day — not because the business is genuinely that lean, but because the denominator is structurally understated. The relative ranking between product categories remains valid and is the meaningful analytical output.

**`number_of_products_sold` has no fixed time unit.**
The field records units sold per transaction, not per day or per week. It cannot be treated as a daily demand rate. This is why the safety stock and ROP query uses it as a demand proxy per transaction rather than labelling it "daily sales" — the statistical formula still produces a valid relative ranking of stockout risk across SKUs, even if the absolute ROP values are not directly comparable to a real daily-demand model.

**`manufacturing_costs` and `shipping_costs` field types are undocumented in the source.**
The original Kaggle dataset does not specify whether these are per-unit or per-shipment fields. Data inspection confirmed that `manufacturing_costs` scales as a per-unit value while `shipping_costs` is a flat per-shipment fee that does not scale with units sold. This distinction required explicit verification before any margin calculation could be trusted.

**`lead_time` vs `manufacturing_lead_time` as an on-time proxy.**
The dataset does not contain a promised or contracted delivery date. `manufacturing_lead_time` is used as the closest available benchmark for expected lead time, and transactions where `lead_time <= manufacturing_lead_time` are counted as on-time. This is an approximation — in a real ERP system, on-time delivery would be calculated against a confirmed purchase order due date.

**`order_quantities` reflects replenishment orders, not customer demand.**
This field represents the quantity ordered from suppliers, not the quantity sold to customers. It is used only in Module 1 BQ3 to measure supplier volume tier and is not used in any demand or revenue calculation.

---

## How to Reproduce

**Prerequisites:** Docker, DBeaver or any PostgreSQL client, Python 3.8+

```bash
# 1. Generate the dataset
cd data/
pip install pandas numpy
python generate_dataset.py
# Output: supply_chain_10k_final.csv

# 2. Start PostgreSQL container
docker run --name supply-chain-db \
  -e POSTGRES_USER=analyst \
  -e POSTGRES_PASSWORD=analyst \
  -e POSTGRES_DB=supply_chain \
  -p 5433:5432 \
  -d postgres:15

# 3. Connect DBeaver
#    Host: localhost | Port: 5433
#    Database: supply_chain
#    Username: analyst | Password: analyst

# 4. Import supply_chain_10k_final.csv as table supply_chain_final
#    Right click public schema → Import Data → CSV

# 5. Run SQL scripts in order
#    sql/01_data_cleaning_and_modeling.sql
#    sql/02_data_analysis.sql
```

---

## Data Source

| | |
|---|---|
| **Original Dataset** | Supply Chain Dataset by Amir Motefaker |
| **Kaggle Link** | https://www.kaggle.com/datasets/amirmotefaker/supply-chain-dataset |
| **License** | Open Database License (ODbL) |
| **Note** | Original 100-row dataset used as product and supplier master data. Transaction history extended to 10,000 rows using Python to simulate realistic supply chain operations across 2022–2023. Generation script available at `data/generate_dataset.py` |

---

## About

Built by **Tuan Thanh Thinh** as part of a data analytics portfolio focused on supply chain and ERP domain knowledge.

Connect on [LinkedIn](https://www.linkedin.com/in/henrythinh0311/) | View other projects on [GitHub](https://github.com/tnth1603)
