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
    │   ├── 04_stockout_risk.png            ← SKUs flagged for urgent reorder by stock level
    │   ├── 05_inventory_turnover.png       ← turnover ratio and movement category by product type
    │   ├── 06_seasonal_demand.png          ← seasonal demand patterns and stock alignment
    │   ├── 07_gross_margin.png             ← gross margin ranking by product type
    │   ├── 08_cost_breakdown.png           ← manufacturing vs shipping cost share per product
    │   └── 09_cost_trend.png              ← quarterly manufacturing cost inflation over 2 years
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
| BQ4 | Has supplier lead time improved or deteriorated over time? | `LAG()`, `PARTITION BY`, trend analysis |

---

### Module 2 — Inventory Management

**Domain relevance:** Inventory is the most visible output of supply chain decisions. Analysts are expected to identify stockout risks, calculate turnover rates and align stock levels with seasonal demand patterns.

| # | Business Question | SQL Techniques |
|---|---|---|
| BQ1 | Which SKUs are critically low and need urgent replenishment? | `CASE` flags, reorder point calculation |
| BQ2 | Which product types turn over fastest vs sitting as dead stock? | Subquery aggregation, `RANK()`, turnover ratio |
| BQ3 | Are we overstocked in any category relative to actual sales? | Window functions, stock-to-sales ratio |
| BQ4 | Which seasons drive highest demand and are stock levels aligned? | `EXTRACT`, seasonal aggregation, `SUM OVER` |

---

### Module 3 — Cost Tracking & Margin Analysis

**Domain relevance:** Cost visibility is essential for procurement decisions. Analysts must identify which products and suppliers deliver the best margins and where cost inflation is occurring.

| # | Business Question | SQL Techniques |
|---|---|---|
| BQ1 | Which product types generate the highest gross margins? | `SUM`, margin calculation, `RANK()` |
| BQ2 | What proportion of total cost is manufacturing vs shipping? | Percentage share, `SUM OVER()` |
| BQ3 | Are manufacturing costs increasing over the 2-year period? | `LAG()`, quarter-over-quarter trend |
| BQ4 | Which suppliers deliver the best revenue-to-cost ratio? | Ratio calculation, efficiency ranking |

---

## SQL Techniques Demonstrated

| Technique | Description |
|---|---|
| `CTEs` | Multi-step query logic using WITH clauses across all modules |
| `Window Functions` | `RANK()`, `LAG()`, `NTILE()`, `SUM OVER()`, `PARTITION BY` |
| `Aggregations` | `GROUP BY`, `HAVING`, `AVG`, `SUM`, `COUNT DISTINCT` |
| `CASE WHEN` | Business logic — risk flags, reorder actions, movement categories |
| `Subqueries` | Per-SKU aggregation before rolling up to product type level |
| `NULLIF()` | Safe division to prevent divide-by-zero errors |
| `CAST()` | Explicit type conversion for accurate ratio calculations |
| `MD5()` | Surrogate key generation for dimension tables |
| `ROW_NUMBER()` | Deduplication using PARTITION BY in staging layer |
| `EXTRACT()` | Date part extraction for time-series and seasonal analysis |
| `CREATE OR REPLACE VIEW` | Reusable layer definitions across landing, staging and marts |
| `LEFT JOIN` | FK resolution across fact and dimension tables |
| Schema separation | Three-schema architecture: landing, staging, marts |

---

## Data Modeling Decisions

**Why views instead of tables for staging and marts?**
Views ensure analysis always reflects the latest landing data without requiring re-runs. This mirrors how production data pipelines work in real ERP environments where source data updates continuously.

**Why ROW_NUMBER() instead of DISTINCT for deduplication?**
DISTINCT on multiple columns preserves all unique combinations — a supplier appearing in 5 cities creates 5 rows. ROW_NUMBER() PARTITION BY the key column picks exactly one canonical row per entity, preventing JOIN fan-out in the fact table. This reduced fact_transactions from 600,000 rows to the correct 10,000.

**Why MD5() for surrogate keys?**
Unlike SERIAL (auto-increment), MD5 produces the same hash for the same input regardless of when the pipeline runs. This makes keys stable and reproducible — critical for incremental loads and pipeline reruns.

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

Connect on [LinkedIn](#) | View other projects on [GitHub](#)
