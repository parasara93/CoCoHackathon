# Silver Layer — Key CoCo Prompts

This file contains only the important reusable prompts used to design, build, validate, recover, and govern the Silver layer for the Supply Chain hackathon.

---

## 1. Define the Approved RAW Source Set

Use this before any Silver design or rebuild.

```text
While designing and creating the Silver layer from the shared RAW database, exclude the manually created test tables that are not part of the finalized synthetic S3 dataset.

Exclude:
- CUSTOMER
- PART
- PLANT
- SUPPLIER
- ORDER_HEADER
- ORDER_LINE
- SHIPMENT

Use only these approved finalized synthetic RAW tables:
- CUSTOMERS
- PARTS
- PLANTS
- SUPPLIERS
- CARRIERS
- ROUTES
- ORDERS
- ORDER_LINES
- SHIPMENTS
- SHIPMENT_LINES
- SHIPMENT_EVENTS
- INVENTORY
- SUPPLIER_PARTS
- SUPPLIER_PERFORMANCE
- VEHICLE_TELEMETRY

Important:
- We only have access to a shared RAW database in this account.
- Do not rely on ingestion history, query history, S3 stage history, or object creation history to determine source lineage.
- Treat the exclusion list above as an explicit business rule.
- Do not infer the correct source from row count, table size, naming similarity, or column count.

Before creating Silver objects:
1. Show the final RAW source list.
2. Show the excluded tables.
3. Confirm the intended fact/dimension/bridge model.
4. Do not create objects until the source scope is confirmed.
```

---

## 2. Build the Silver Dimensional Model

Use this after the RAW source set is confirmed.

```text
Build the Silver dimensional model from the approved RAW tables.

Target logical model:

Dimensions:
- DIM_DATE
- DIM_CUSTOMER
- DIM_PART
- DIM_PLANT
- DIM_SUPPLIER
- DIM_CARRIER
- DIM_ROUTE

Facts:
- FACT_ORDER_LINE
- FACT_SHIPMENT
- FACT_SHIPMENT_LINE
- FACT_SHIPMENT_EVENT
- FACT_INVENTORY_SNAPSHOT
- FACT_SUPPLIER_PERFORMANCE
- FACT_VEHICLE_TELEMETRY

Bridge:
- BRIDGE_SUPPLIER_PART

Before creating each object, state:
- target grain
- business key
- source table(s)
- join keys
- deduplication/version-resolution logic if required
- derived columns
- potential fan-out risks

Important:
- Do not blindly copy RAW duplicates into Silver.
- Do not collapse genuine event history such as SHIPMENT_EVENTS or VEHICLE_TELEMETRY.
- Do not hardcode synthetic scenario IDs into transformation logic.
```

---

## 3. Comprehensive Silver Validation

Use immediately after the first Silver build.

```text
Run a complete structural and data-quality validation of the Silver dimensional model.

Do not modify data during this validation.

Validate:

1. Fact grain uniqueness
- FACT_ORDER_LINE
- FACT_SHIPMENT
- FACT_SHIPMENT_LINE
- FACT_SHIPMENT_EVENT
- FACT_INVENTORY_SNAPSHOT
- FACT_SUPPLIER_PERFORMANCE
- FACT_VEHICLE_TELEMETRY

2. Dimension key uniqueness and NULL business keys
- DIM_DATE
- DIM_CUSTOMER
- DIM_PART
- DIM_PLANT
- DIM_SUPPLIER
- DIM_CARRIER
- DIM_ROUTE

3. Bridge grain
- BRIDGE_SUPPLIER_PART must be unique at SUPPLIER_ID + PART_ID

4. Referential integrity
Check all fact/dimension and bridge relationships and report orphan counts.

5. Derived columns
Validate:
- IS_ON_TIME
- ACTUAL_TRANSIT_HOURS
- PLANNED_TRANSIT_HOURS
- NEEDS_REORDER
- BELOW_SAFETY_STOCK

6. Join fan-out
Identify any Silver table where joins increased the declared grain.

7. Scenario preservation
Confirm that synthetic scenario behavior remains detectable without adding scenario-label columns to operational Silver tables.

Return PASS/FAIL for every check and explain every failure before proposing a fix.
```

---

## 4. Resolve Incremental-Version Duplicates

Use if RAW contains multiple versions because incremental files were appended without MERGE/upsert.

```text
The RAW layer contains multiple versions of some business records because generated incremental files were appended without update/upsert logic.

Silver should resolve those versions into the correct analytical state while preserving genuine history.

Validate and apply the appropriate latest-version logic:

- ORDERS:
  latest row per ORDER_ID using the appropriate update timestamp

- ORDER_LINES:
  latest row per ORDER_LINE_ID

- SHIPMENTS:
  latest row per SHIPMENT_ID

- INVENTORY:
  latest row per PLANT_ID + PART_ID

- SUPPLIER_PERFORMANCE:
  confirm the intended business grain first, then keep the latest version within that grain

- SUPPLIER_PARTS:
  latest row per SUPPLIER_ID + PART_ID

Do not use blind DISTINCT.

Before rebuilding:
1. confirm the partition/business key
2. confirm the timestamp used for version ordering
3. check for ties at the maximum timestamp
4. report which business attributes differ between versions

Do not collapse:
- SHIPMENT_EVENTS
- VEHICLE_TELEMETRY

After rebuilding, rerun the full Silver validation suite.
```

---

## 5. Fix IS_ON_TIME Logic

Use if undelivered shipments are being marked late.

```text
Correct FACT_SHIPMENT.IS_ON_TIME.

Required logic:

CASE
    WHEN ACTUAL_DELIVERY_AT IS NULL THEN NULL
    WHEN ACTUAL_DELIVERY_AT <= PLANNED_DELIVERY_AT THEN TRUE
    ELSE FALSE
END

Meaning:
- TRUE = delivered on time
- FALSE = delivered late
- NULL = not yet determinable

After the change:
- validate all non-null delivery rows
- confirm undelivered shipments remain NULL
- do not mix overdue/open-shipment logic into IS_ON_TIME
```

---

## 6. Restructure Silver into the Project Database

Use after the Silver logic is validated.

```text
Restructure the validated Silver layer into:

SUPPLY_CHAIN_DW.SILVER

Current source:
SUPPLY_CHAIN_SILVER.DIMENSIONAL

Move/recreate the validated 15 Silver objects under the SILVER schema.

Requirements:
- preserve current validated grains, keys, data types, derived columns, and dedup logic
- do not redesign the model
- do not create Gold objects
- do not drop the old Silver objects until the new structure is fully validated
- check constraints, clustering keys, grants, policies, and tags before cloning/recreating

After restructuring, rerun:
- table count
- row counts
- grain uniqueness
- dimension key uniqueness
- RI
- derived-column validation
- scenario-preservation checks

Return the old-to-new object mapping and PASS/FAIL comparison.
```

---

## 7. Recover the Validated Silver Implementation into Git

Use after the final Silver structure is stable.

```text
Recover the current validated Silver implementation into version-controlled project files.

Current baseline:
SUPPLY_CHAIN_DW.SILVER

Create/populate:

silver/
  dimensions/
  facts/
  bridges/

validations/
  silver/

AGENTS.md

For each Silver object:
- recover the actual transformation SQL needed to rebuild it from RAW
- do not recover only CREATE TABLE column DDL
- preserve validated dedup/version-resolution logic
- preserve derived-column logic
- do not invent transformation logic if existing validated SQL can be recovered

Create reusable validation files for:
- grain checks
- dimension key checks
- referential integrity
- derived columns
- scenario checks

Do not rebuild or modify Snowflake during the recovery task.

Return:
1. file tree
2. file-to-object mapping
3. what was recovered exactly
4. any reconstructed logic
5. gaps requiring manual review
```

---

## 8. Permanent Silver Modeling Rules for AGENTS.md

These are not one-time prompts. Keep them as project instructions.

```text
- Before creating or modifying any fact, bridge, mart, or other grain-sensitive object, explicitly state the intended target grain and business key(s).

- When joining multiple fact-like or many-side datasets, aggregate each source to the intended target grain before joining. Do not allow row multiplication or fan-out.

- Never hardcode synthetic scenario IDs, scenario names, target entities, or expected outcomes into transformation logic. Scenario-specific values may only be used in validation/reference queries.

- Persistent Snowflake changes must be represented in version-controlled SQL.

- Never treat chat history as the source of truth.

- After persistent changes, validate grain, referential integrity, derived logic, and scenario behavior.
```

---

## Silver Completion Criteria

Silver can be considered complete for the current non-CDC baseline when:

- the approved RAW source set is enforced
- all 15 Silver objects exist under `SUPPLY_CHAIN_DW.SILVER`
- declared grains are unique
- referential integrity passes
- derived columns are validated
- append-only RAW version duplicates are resolved correctly
- genuine event history remains intact
- validation SQL is version-controlled
- Silver build SQL is version-controlled
- project instructions and migration/change-management rules are in place

CDC with Streams/Tasks is intentionally deferred to a later phase.
