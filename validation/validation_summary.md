# Synthetic Data Validation Summary

## Overview

This document summarizes the validation performed on the synthetic supply-chain dataset generated for the Resilient Supply Chain hackathon project.

The generator was validated progressively using:

1. Tiny preset
2. Medium preset
3. Medium incremental CSV output
4. Full preset

Validation covered:

- Primary-key integrity
- Foreign-key integrity
- Timestamp consistency
- Business rules
- Scenario propagation
- Incremental batch generation
- CSV schema consistency
- Row reconciliation
- Route plausibility
- IoT telemetry behavior

---

## Final Full Dataset

| Table | Rows |
|---|---:|
| customers | 1,500 |
| plants | 15 |
| suppliers | 75 |
| parts | 750 |
| carriers | 20 |
| routes | 200 |
| supplier_parts | 1,875 |
| supplier_performance | 900 |
| orders | 50,000 |
| order_lines | 149,756 |
| inventory | 2,250 |
| shipments | 60,000 |
| shipment_lines | 180,115 |
| shipment_events | 181,725 |
| vehicle_telemetry | 2,024,304 |
| scenario_ground_truth | 5 |

The final full execution used 50,000 orders and 60,000 shipments instead of the original target of approximately 100,000 orders and 120,000 shipments because of local machine memory constraints.

The reduced volume preserves the same schema, relationships, scenario logic, batching logic, and validation behavior.

---

## Standard Validation Results

| Validation | Result |
|---|---|
| Primary keys unique | PASS |
| Foreign keys valid | PASS |
| Timestamp validation | PASS |
| Business rules | PASS |
| CSV schemas | PASS |
| Batch chronology | PASS |
| Timeline boundaries | PASS |
| Duplicate insert validation | PASS |
| Row reconciliation | PASS |
| Scenario propagation | PASS |

All 16 generated datasets reconciled successfully.

There were:

- 0 missing records
- 0 unexpected base records
- 0 duplicate inserts

---

## Incremental File Strategy

The overall dataset covers a 12-month synthetic timeline.

### Historical period

Historical data is emitted as larger backfill files, generally monthly.

Static/reference tables such as:

- customers
- plants
- suppliers
- parts
- carriers
- routes

are emitted as historical files and do not generate unnecessary empty incremental files.

### Incremental period

The final 7 days are used to emulate operational incremental ingestion.

ERP, Supplier, and Logistics datasets use:

- 06:30
- 09:30
- 12:30
- 15:30
- 18:30

IoT vehicle telemetry uses hourly batching.

Empty incremental files are skipped.

---

## Final CSV Output

| Metric | Count |
|---|---:|
| Total CSV files | 538 |
| Historical files | 115 |
| Incremental files | 423 |
| Empty batches skipped | 25 |

---

## IoT Validation

Vehicle telemetry is split into:

- base telemetry produced by the core generator
- supplemental hourly telemetry generated for the final 7-day incremental simulation

| Metric | Value |
|---|---:|
| Base telemetry | 2,024,304 |
| Supplemental telemetry | 8,163 |
| Total telemetry in files | 2,032,467 |
| Historical monthly files | 12 |
| Incremental hourly files | 168 |
| Hourly slots populated | 168 / 168 |
| Incremental telemetry rows | 114,412 |
| Average rows per hourly batch | 681 |

Supplemental telemetry is intentionally generated and is explicitly accounted for during reconciliation.

Delivered/inactive shipments do not continue producing active incremental telemetry.

---

## Full Reconciliation

Every operational dataset was reconciled against the emitted historical and incremental files.

All 16 datasets passed.

Examples:

- Orders: 50,000 source records → 50,000 file records
- Order lines: 149,756 → 149,756
- Shipments: 60,000 → 60,000
- Shipment lines: 180,115 → 180,115
- Shipment events: 181,725 → 181,725

Vehicle telemetry contains 8,163 additional expected supplemental hourly records.

---

## Route Plausibility

Route distance generation was changed from independent random distances to geography-aware generation.

The generator:

1. resolves source/destination coordinates
2. calculates haversine distance
3. applies a deterministic route multiplier between 1.2x and 1.8x
4. derives expected transit time using a realistic effective speed range

Validation checks include:

- route distance >= straight-line distance
- reasonable route-to-straight-line ratio
- plausible average transport speed
- valid origin/destination geography

---

## Generator Performance

| Phase | Time |
|---|---:|
| Generation | 340 seconds |
| CSV write | 124 seconds |
| CSV validation | 82.9 seconds |
| Reconciliation | 81 seconds |
| Total | approximately 10.5 minutes |
| Peak Python memory | approximately 1.0 GB |

The generator was optimized to reduce memory pressure by removing expensive row-wise operations and using more efficient/chunked generation for high-volume datasets.

---

## Final Status

All required integrity validations pass.

All five disruption scenarios are observable across their intended domains.

The generated dataset is considered ready for:

- S3 landing
- Snowflake RAW ingestion
- incremental pipeline development
- semantic modeling
- supply-chain analytics
- agent-based investigation
- Streamlit visualization