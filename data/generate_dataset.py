"""
Supply Chain Dataset Generator
================================
Extends the original 100-row Amir Motefaker Supply Chain Dataset
(Kaggle) into a 10,000-row transaction dataset with realistic patterns.

Original dataset: https://www.kaggle.com/datasets/amirmotefaker/supply-chain-dataset
Place the original CSV as 'supply_chain_data.csv' in the same folder before running.

Usage:
    python generate_dataset.py

Output:
    supply_chain_10k_final.csv
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random

random.seed(42)
np.random.seed(42)

# ── LOAD ORIGINAL MASTER DATA ─────────────────────────────────────────────────
df_orig = pd.read_csv('supply_chain_data.csv')

skus          = df_orig['SKU'].tolist()
product_types = dict(zip(df_orig['SKU'], df_orig['Product type']))
base_prices   = dict(zip(df_orig['SKU'], df_orig['Price']))
base_mfg_cost = dict(zip(df_orig['SKU'], df_orig['Manufacturing costs']))
base_defect   = dict(zip(df_orig['SKU'], df_orig['Defect rates']))
base_mfg_lt   = dict(zip(df_orig['SKU'], df_orig['Manufacturing lead time']))
sku_suppliers = dict(zip(df_orig['SKU'], df_orig['Supplier name']))
sku_locations = dict(zip(df_orig['SKU'], df_orig['Location']))
sku_routes    = dict(zip(df_orig['SKU'], df_orig['Routes']))
sku_transport = dict(zip(df_orig['SKU'], df_orig['Transportation modes']))

carriers = df_orig['Shipping carriers'].unique().tolist()

# ── SUPPLIER RELIABILITY PROFILES ─────────────────────────────────────────────
# Intentional variation: Supplier 1 = best, Supplier 5 = worst
supplier_profile = {
    'Supplier 1': {'delay_factor': 0.8,  'defect_factor': 0.7},
    'Supplier 2': {'delay_factor': 1.0,  'defect_factor': 1.0},
    'Supplier 3': {'delay_factor': 1.1,  'defect_factor': 1.2},
    'Supplier 4': {'delay_factor': 1.3,  'defect_factor': 1.5},
    'Supplier 5': {'delay_factor': 1.6,  'defect_factor': 2.0},
}

# ── CARRIER PROFILES ──────────────────────────────────────────────────────────
carrier_profile = {
    'Carrier A': {'speed': 2, 'cost_factor': 1.2},  # fast, expensive
    'Carrier B': {'speed': 4, 'cost_factor': 0.9},  # slow, cheap
    'Carrier C': {'speed': 3, 'cost_factor': 1.0},  # balanced
}

# ── SEASONAL DEMAND MULTIPLIERS ───────────────────────────────────────────────
# Higher demand in Nov/Dec (holiday season), lower in Jan/Feb
season_demand = {
    1: 0.8, 2: 0.8, 3: 0.9,  4: 1.0,
    5: 1.1, 6: 1.2, 7: 1.2,  8: 1.1,
    9: 1.0, 10: 1.1, 11: 1.3, 12: 1.5
}

# ── GENERATE 10,000 TRANSACTIONS ──────────────────────────────────────────────
start_date = datetime(2022, 1, 1)
end_date   = datetime(2023, 12, 31)
date_range = (end_date - start_date).days

records = []
for i in range(10000):
    sku       = random.choice(skus)
    ptype     = product_types[sku]
    supplier  = sku_suppliers[sku]
    location  = sku_locations[sku]
    route     = sku_routes[sku]
    transport = sku_transport[sku]
    carrier   = random.choice(carriers)

    tx_date       = start_date + timedelta(days=random.randint(0, date_range))
    month         = tx_date.month
    seasonal_mult = season_demand[month]

    # Price with seasonal variation ± 8%
    price         = round(base_prices[sku] * np.random.uniform(0.92, 1.08), 2)
    products_sold = max(1, int(np.random.normal(loc=200 * seasonal_mult, scale=80)))
    revenue       = round(price * products_sold * np.random.uniform(0.85, 1.15), 2)
    stock_levels  = max(0, int(np.random.normal(loc=80 - products_sold * 0.05, scale=20)))
    availability  = min(100, max(0, int(stock_levels * np.random.uniform(0.7, 1.1))))
    order_qty     = max(1, int(np.random.normal(loc=60, scale=25)))

    # Lead time affected by supplier reliability profile
    sp            = supplier_profile[supplier]
    cp            = carrier_profile[carrier]
    base_lt       = base_mfg_lt[sku]
    lead_time     = max(1, int(base_lt * sp['delay_factor'] * np.random.uniform(0.8, 1.3)))
    lead_times_var= max(1, int(lead_time * np.random.uniform(0.9, 1.1)))
    shipping_time = max(1, int(cp['speed'] * np.random.uniform(0.8, 1.4)))
    shipping_cost = round(base_prices[sku] * 0.05 * cp['cost_factor'] * np.random.uniform(0.7, 1.3), 2)

    # Manufacturing cost with ~2.4% annual inflation
    months_elapsed = (tx_date - start_date).days / 30
    inflation      = 1 + (months_elapsed * 0.002)
    mfg_cost       = round(base_mfg_cost[sku] * inflation * np.random.uniform(0.9, 1.1), 2)

    # Defect rate affected by supplier profile
    prod_vol    = max(1, int(np.random.normal(loc=500, scale=200)))
    defect_rate = round(base_defect[sku] * sp['defect_factor'] * np.random.uniform(0.5, 1.5), 4)
    defect_rate = max(0.0, min(15.0, defect_rate))

    if defect_rate < 2.0:   inspection = 'Pass'
    elif defect_rate < 4.0: inspection = 'Pending'
    else:                   inspection = 'Fail'

    mfg_lead_time = max(1, int(base_lt * sp['delay_factor'] * np.random.uniform(0.85, 1.15)))
    total_cost    = round(mfg_cost * order_qty + shipping_cost * order_qty, 2)

    records.append({
        'Transaction ID'          : f'TXN{str(i + 1).zfill(5)}',
        'Transaction Date'        : tx_date.strftime('%Y-%m-%d'),
        'Product Type'            : ptype,
        'SKU'                     : sku,
        'Price'                   : price,
        'Availability'            : availability,
        'Number of Products Sold' : products_sold,
        'Revenue Generated'       : revenue,
        'Stock Levels'            : stock_levels,
        'Lead Times'              : lead_times_var,
        'Order Quantities'        : order_qty,
        'Shipping Times'          : shipping_time,
        'Shipping Carriers'       : carrier,
        'Shipping Costs'          : shipping_cost,
        'Supplier Name'           : supplier,
        'Location'                : location,
        'Lead Time'               : lead_time,
        'Production Volumes'      : prod_vol,
        'Manufacturing Lead Time' : mfg_lead_time,
        'Manufacturing Costs'     : mfg_cost,
        'Inspection Results'      : inspection,
        'Defect Rates'            : defect_rate,
        'Transportation Modes'    : transport,
        'Routes'                  : route,
        'Total Logistics Cost'    : total_cost,
    })

df = pd.DataFrame(records).sort_values('Transaction Date').reset_index(drop=True)

df.to_csv('supply_chain_10k_final.csv', index=False)
print(f"Dataset generated: {len(df):,} rows × {len(df.columns)} columns")
print(f"Date range: {df['Transaction Date'].min()} to {df['Transaction Date'].max()}")
print(f"Suppliers: {df['Supplier Name'].unique()}")
print(f"Product types: {df['Product Type'].unique()}")
