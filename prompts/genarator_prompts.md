# CoCo Development Prompts

This file contains the major prompts used to iteratively build and validate the synthetic supply-chain data generator with Snowflake CoCo.

Only milestone prompts are included.

Debugging prompts, crash investigations, and one-off troubleshooting prompts are intentionally omitted.

---

# 1. Generator Skeleton

Read `DATA_GENERATION_CONTRACT.md`.

Do not generate the full synthetic dataset.

Create a Python synthetic-data generator skeleton that follows the contract exactly.

For this step only:

- define the table schemas
- define the primary-key and foreign-key relationships
- define configurable row-count parameters
- define a deterministic random seed
- create separate generator functions for ERP, Supplier, Logistics, and IoT domains
- create validation functions for primary keys, foreign keys, timestamps, and basic business rules
- create placeholders for scenario injection, but do not implement the five scenarios yet
- do not upload anything to S3
- do not create Snowflake objects
- do not generate large CSV files

Keep the code modular so that row counts can later be switched between tiny sample, medium test, and full generation.

Before writing code, summarize the planned Python modules/functions in a concise list.

Then implement them.

---

# 2. Generator Structure Correction

Before implementation, correct the proposed structure so it exactly matches `DATA_GENERATION_CONTRACT.md`.

There are 15 operational tables.

ERP:

- customers
- plants
- orders
- order_lines
- inventory

Supplier:

- suppliers
- parts
- supplier_parts
- supplier_performance

Logistics:

- carriers
- routes
- shipments
- shipment_lines
- shipment_events

IoT:

- vehicle_telemetry

Scenario validation:

- scenario_ground_truth is a separate validation output, not an operational table.

Move `gen_parts` to the Supplier generator section.

Add:

- `gen_supplier_performance`
- `gen_shipment_events`

Use only the five finalized scenarios:

- Supplier Deterioration
- Inventory Shortage
- Plant Bottleneck
- Logistics / Transportation Cost Disruption
- Customer Impact

Do not create additional scenarios.

Keep all scenario functions as placeholders until the base generator has passed validation.

---

# 3. Tiny Preset Implementation

Proceed with implementation.

Constraints:

1. `generate_all()` must generate tables in true dependency order even when dependencies cross source domains.

2. Define tiny, medium, and full presets, but initially execute only the tiny preset.

Keep all five scenario injection functions as placeholders.

After implementation, run the tiny preset and report:

- row count for every table
- primary-key validation
- foreign-key validation
- timestamp validation
- business-rule validation

Do not proceed beyond the tiny validation run.

---

# 4. Scenario 1 — Supplier Deterioration

Implement only `inject_supplier_deterioration`.

Do not implement the other scenarios yet.

Requirements:

- select one deterministic supplier
- ensure the supplier provides actively used parts
- create a deterioration window inside the configured timeline
- increase average lead time
- reduce on-time delivery percentage
- reduce fill rate
- increase supplier risk
- delay related inbound shipments
- reduce/delay replenishment of affected inventory
- create downstream order fulfillment risk

Do not add scenario labels to operational tables.

Store scenario identification only in `scenario_ground_truth`.

After injection, rerun standard validation and add cross-domain scenario validation.

---

# 5. Scenario 2 — Inventory Shortage

Implement the Inventory Shortage scenario.

Requirements:

- deterministically select critical/high-criticality parts
- reduce available inventory for those parts
- breach safety stock for affected plant-part combinations
- cause related order lines to remain unfulfilled or delayed
- affect related parent orders
- delay appropriate outbound shipments
- expose customer delivery risk

Keep the scenario fully inside the configured synthetic timeline.

Do not add scenario labels to operational tables.

Run all standard and scenario-specific validations.

---

# 6. Scenario 3 — Plant Bottleneck

Implement the Plant Bottleneck scenario.

The bottleneck must create observable operational pressure.

Requirements:

- increase inventory reservations
- reduce available inventory
- increase measurable order backlog
- create an observable processing delay
- delay related outbound shipments
- increase customer delivery risk

Do not unrealistically regress advanced order statuses.

For already partially shipped orders:

- keep the valid order status
- stall remaining unfulfilled lines where appropriate
- represent processing delay through timestamps

Validation must require:

backlog_after > backlog_before

---

# 7. Scenario 4 — Logistics Disruption

Implement the Logistics / Transportation Cost Disruption scenario.

Requirements:

- select a deterministic route
- increase route transit time
- delay shipments using the route
- increase shipping/transportation cost
- inject DELAY_REPORTED and ROUTE_DEVIATION events
- ensure vehicle telemetry exposes DELAYED/OFF_ROUTE behavior
- expose downstream fulfillment impact

Do not describe shipping-cost changes as full landed cost.

Route plausibility must be validated using geography.

---

# 8. Scenario 5 — Customer Impact

Implement Customer Impact as a culmination scenario.

Do not create an independent random disruption.

Identify customer orders affected by Scenarios 1–4.

Expose downstream effects including:

- delivery-date breaches
- partial fulfillment where appropriate
- delayed customer orders
- customer-level service-risk metrics

All effects must trace back to upstream disruption.

---

# 9. Medium Preset Validation

Run the synthetic data generator using the `medium` preset.

Do not change:

- schemas
- scenarios
- business rules
- validation logic
- deterministic seed

Run:

- PK validation
- FK validation
- timestamp validation
- business-rule validation
- all scenario validations

Report:

- row counts
- scenario targets
- affected record counts
- whether fallback logic was required
- runtime
- peak memory

Do not generate full data yet.

---

# 10. Medium Incremental CSV Generation

Extend the generator to produce incremental CSV files from the medium preset.

Use the full 12-month timeline.

Only the final 7 days should simulate incremental ingestion.

Earlier data should be emitted as historical/backfill files.

ERP, Supplier, and Logistics changing tables:

- 06:30
- 09:30
- 12:30
- 15:30
- 18:30

IoT:

- hourly telemetry batches for active shipments

Do not generate empty files merely to represent batch slots.

Static/reference tables should remain historical-only when they do not change.

Validate:

- CSV schemas
- PK uniqueness
- FK integrity
- stable update keys
- insert collisions
- chronological batches
- row reconciliation
- scenario propagation after splitting
- IoT behavior

Do not upload to S3.

---

# 11. Medium CSV Cleanup and Reconciliation

Before moving to full generation:

- remove unnecessary empty incremental files
- keep static tables historical-only
- ensure final-week IoT contains realistic hourly activity
- reconcile every generated base record against historical + incremental files

For every table report:

- generated/source count
- unique inserted records in files
- missing records
- unexpected records
- duplicate inserts

Supplemental hourly telemetry must be tracked separately from base telemetry.

Do not proceed to full generation until reconciliation passes.

---

# 12. Route Plausibility Fix

Adjust route generation so `distance_km` is derived consistently from origin/destination geography.

Use:

1. origin/destination coordinates
2. haversine distance
3. deterministic route multiplier
4. plausible effective transport speed

Requirements:

- route distance >= straight-line distance
- route/straight-line ratio remains reasonable
- expected transit hours agree with route distance
- effective average speed is plausible
- deterministic generation remains intact

Do not change scenario or batching logic.

---

# 13. Full Preset Generation

Run the synthetic data generator using the full preset.

Do not redesign:

- schemas
- scenarios
- route logic
- batching logic
- validation logic
- deterministic seed
- file naming

Use the same validated behavior from the medium preset.

Generate:

- full 12-month dataset
- final 7 days as incremental simulation
- five daily batches for changing ERP/Supplier/Logistics data
- hourly IoT batches for active shipments

Do not generate empty CSV files.

Run all validations:

- primary keys
- foreign keys
- timestamps
- business rules
- CSV schemas
- batch chronology
- row reconciliation
- scenario propagation
- route plausibility
- timeline bounds
- duplicate inserts

Report:

- final row counts
- file counts
- historical vs incremental split
- insert/update counts
- IoT base and supplemental telemetry
- scenario targets
- scenario affected counts
- reconciliation
- runtime
- peak memory
- any fallback/workaround used

Do not upload anything to S3 yet.

Stop after the full validation summary.