# AGENTS.md — Project Instructions

## Validated Silver Baseline

`SUPPLY_CHAIN_DW.SILVER` is the validated Silver baseline. All 15 tables have passed grain uniqueness, dimension key uniqueness, referential integrity, derived-column validation, deduplication/version-resolution checks, bridge uniqueness, and scenario-preservation checks.

## Rules

1. **Version-controlled SQL is the source of truth.** All persistent Snowflake changes must be represented in version-controlled SQL files under `silver/`, `validations/`, or `migrations/`.

2. **Declare target grain before creating or changing analytical objects.** Every fact, dimension, or bridge must state its grain (primary key / composite key) before creation.

3. **Check for many-to-many fan-out before joining facts.** If joining two fact tables, verify that the join key is unique on at least one side to avoid row multiplication.

4. **Validate after changes.** After any Silver-layer change, run:
   - Grain checks (`validations/silver/grain_checks.sql`)
   - Dimension key checks (`validations/silver/dimension_key_checks.sql`)
   - Referential integrity checks (`validations/silver/referential_integrity.sql`)
   - Derived column checks (`validations/silver/derived_column_checks.sql`)
   - Scenario preservation checks (`validations/silver/scenario_checks.sql`)

5. **Do not use excluded RAW test tables.** The following tables in `SUPPLY_CHAIN_RAW_DATASET.RAW` are manual/test tables and must not be used:
   - `CUSTOMER`, `PART`, `PLANT`, `SUPPLIER`, `ORDER_HEADER`, `ORDER_LINE`, `SHIPMENT`, `SUPPLIER_PART`

   Use only the approved RAW tables:
   - `CUSTOMERS`, `PARTS`, `PLANTS`, `SUPPLIERS`, `CARRIERS`, `ROUTES`, `ORDERS`, `ORDER_LINES`, `SHIPMENTS`, `SHIPMENT_LINES`, `SHIPMENT_EVENTS`, `INVENTORY`, `SUPPLIER_PARTS`, `SUPPLIER_PERFORMANCE`, `VEHICLE_TELEMETRY`

6. **Do not modify previously applied migration files.** If a migration has been applied to Snowflake, never edit it. Create a new migration file under `migrations/` for any future schema change.

7. **Do not treat chat history as the source of truth.** The validated state is defined by the current Snowflake objects and the version-controlled SQL files. Chat conversations are ephemeral context, not authoritative records.

## RAW Source Database

All RAW data is sourced from `SUPPLY_CHAIN_RAW_DATASET.RAW`.

## Deduplication Rules

Mutable/versioned RAW entities use `ROW_NUMBER() OVER (PARTITION BY <key> ORDER BY LAST_UPDATED_AT DESC)`:

| RAW Table | Dedup Key |
|---|---|
| ORDERS | ORDER_ID |
| ORDER_LINES | ORDER_LINE_ID |
| SHIPMENTS | SHIPMENT_ID |
| INVENTORY | PLANT_ID + PART_ID |
| SUPPLIER_PERFORMANCE | SUPPLIER_ID + MEASUREMENT_DATE |
| SUPPLIER_PARTS | SUPPLIER_ID + PART_ID |

History tables (SHIPMENT_EVENTS, VEHICLE_TELEMETRY) and static reference tables are NOT deduplicated.

## Derived Column Definitions

| Column | Table | Expression |
|---|---|---|
| IS_ON_TIME | FACT_SHIPMENT | NULL when ACTUAL_DELIVERY_AT IS NULL; TRUE when <= PLANNED_DELIVERY_AT; FALSE otherwise |
| ACTUAL_TRANSIT_HOURS | FACT_SHIPMENT | DATEDIFF('HOUR', ACTUAL_DEPARTURE_AT, ACTUAL_DELIVERY_AT) |
| PLANNED_TRANSIT_HOURS | FACT_SHIPMENT | DATEDIFF('HOUR', PLANNED_DEPARTURE_AT, PLANNED_DELIVERY_AT) |
| NEEDS_REORDER | FACT_INVENTORY_SNAPSHOT | AVAILABLE_QTY <= REORDER_POINT |
| BELOW_SAFETY_STOCK | FACT_INVENTORY_SNAPSHOT | AVAILABLE_QTY <= SAFETY_STOCK |

## Scenario IDs

Scenario IDs from `scenario_ground_truth` may appear in validation/reference queries but must NEVER be hardcoded into Silver transformation logic.
