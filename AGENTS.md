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

## Data Modeling and Validation Rules

- Before creating or modifying any fact table, bridge, analytical mart, or other grain-sensitive object, explicitly state the intended target grain and the business key(s) that enforce that grain.

- When joining multiple fact-like or many-side datasets, aggregate each source to the intended target grain before joining. Do not join detailed fact tables directly if doing so can create row multiplication or fan-out.

- Never hardcode synthetic scenario IDs, scenario names, expected target entities, or expected outcomes into transformation logic. Scenario-specific IDs and expected results may only be used in validation/reference queries to confirm that the generated scenarios remain detectable after transformation.

## Historical Replay, CDC, and Data-Loading Operations

The following rules govern batch loading, historical replay, CDC (change data capture), MERGE/upsert execution, reconciliation, and audit work — collectively referred to as **DML/orchestration work**. This work is distinct from schema-change work.

1. **Reuse existing objects.** Reuse existing RAW tables, Silver tables, migrations, transformations, and validations wherever possible. Do not recreate RAW or Silver objects unless explicitly required by a new business requirement.

2. **DML/orchestration is not schema-change work.** COPY INTO, batch loading, historical replay, MERGE, reconciliation, validation execution, and audit logging are DML/orchestration activities. They do not require schemachange migrations or the `schema-change` skill unless Snowflake object definitions (CREATE, ALTER, DROP) are also involved.

3. **Invoke `schema-change` only for DDL.** If a CDC or replay task requires creating or altering tables, streams, tasks, procedures, stages, file formats, or control/audit objects, use the `schema-change` skill for those DDL changes only. The data-loading and MERGE execution that follows is DML/orchestration, not schema-change work.

4. **Preserve Silver grain and deduplication logic.** Existing Silver grain definitions and previously approved deduplication logic (see Deduplication Rules above) must not be altered by data-loading or replay work. New data must flow through the same deduplication and transformation rules.

5. **Use ingestion metadata for batch identification.** For incremental processing, identify the processing batch using ingestion metadata such as `LOAD_BATCH_ID`. Do not use business timestamps as the primary ingestion cursor.

6. **Business timestamps for version resolution only.** Business timestamps such as `LAST_UPDATED_AT` may still be used to determine which version of a business record should win during an upsert, consistent with the existing deduplication rules.

7. **Validate after data changes.** Existing validation rules (`validations/silver/` and `validations/gold/`) must continue to run after changes affecting RAW → Silver processing. The same validation suite that covers schema changes also covers data-loading correctness.

## Change Management (schemachange)

All persistent Snowflake schema changes are managed through version-controlled migration files under `migrations/` using [schemachange](https://github.com/Snowflake-Labs/schemachange). See `docs/change-management.md` for full details.

### Persistent DDL rule

Do not directly make persistent Snowflake schema changes first. For any new or modified persistent object:

1. Inspect the current state
2. Define the intended change
3. Create a new migration file under `migrations/`
4. Show the migration diff
5. Validate the migration logic
6. Execute through schemachange
7. Run the relevant validation SQL
8. Report the result

### Versioned migrations

Use versioned migrations for one-time structural changes:

```text
V<major>.<minor>.<patch>__<description>.sql
```

Examples:
- `V1.1.0__add_supplier_risk_columns.sql`
- `V1.2.0__create_inventory_risk_view.sql`
- `V2.0.0__create_gold_schema.sql`

Never edit an already-applied versioned migration. Create a new migration instead.

### Repeatable migrations

Use `R__<description>.sql` only for objects that are intentionally reapplied when their definition changes:

- Views (`CREATE OR REPLACE VIEW`)
- Functions (`CREATE OR REPLACE FUNCTION`)
- Stored procedures (`CREATE OR REPLACE PROCEDURE`)

Do not use repeatable migrations for table structure changes.

### Always migrations

Do not use `A__` scripts unless there is a specific justified need.

### Version ranges

| Range | Purpose |
|---|---|
| V1.0.0 | Silver baseline (no-op, auto-recorded by schemachange) |
| V1.1.0+ | Silver-layer additions/modifications |
| V2.0.0+ | Gold-layer creation and changes |
| V3.0.0+ | Reserved for future layers or major refactors |

### Change history

Migration tracking is stored in `SUPPLY_CHAIN_DW.SCHEMACHANGE.CHANGE_HISTORY`. Configuration lives in `schemachange-config.yml` (config version 2).

### Schema change governance

The authoritative change-management state is the combination of migration files in Git **plus** `SUPPLY_CHAIN_DW.SCHEMACHANGE.CHANGE_HISTORY`. Both must agree.

1. **All persistent Snowflake object changes must be executed through schemachange.** Do not bypass schemachange by executing migration SQL directly through ad-hoc SQL tools, `snowflake_sql_execute`, or any other mechanism — even if it is more convenient.

2. **Do not manually write to `CHANGE_HISTORY`.** Never insert, update, delete, or otherwise edit rows in `SUPPLY_CHAIN_DW.SCHEMACHANGE.CHANGE_HISTORY`. Only schemachange itself may write to this table.

3. **If schemachange is unavailable in the current execution environment:**
   - Create the migration file under `migrations/`.
   - Create or update the relevant validation SQL under `validations/`.
   - **Do not execute the migration directly.**
   - Stop and report: `"Migration prepared; execution pending through schemachange."`
   - The user or CI/CD pipeline executes externally through a working schemachange environment.

4. **Before deployment**, run `schemachange deploy --dry-run` and inspect pending migrations. Do not proceed blindly if the change history and Git are out of sync (e.g., unexpected older versions pending, checksum drift).

5. **After deployment**, run the relevant validation suite (`validations/silver/` or `validations/gold/`) and report PASS/FAIL results.

6. **Already-applied versioned migration files are immutable.** Never edit an applied migration; create the next versioned migration instead.
