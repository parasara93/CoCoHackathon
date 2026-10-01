---
name: build-and-validate-mart
description: Workflow for designing, building, and validating an analytical mart (Gold layer) from the validated Silver layer. Use when creating or modifying Gold analytical marts, KPI tables, summary tables, or denormalized analytical objects.
---

# Build and Validate Mart

Repeatable workflow for designing, building, and validating analytical marts from the validated Silver baseline.

See `AGENTS.md` for permanent project rules (Silver baseline, deduplication keys, derived columns, excluded RAW tables, data modeling rules, validation suite, migration conventions).

## Skill Precedence

**This skill takes precedence** over `schema-change` when the request is primarily about creating, modifying, or extending a Gold analytical mart, business-facing analytical summary, KPI mart, risk mart, control-tower mart, or similar analytical output.

Examples that should trigger this skill (not `schema-change`):

- "Create a supplier risk mart"
- "Build a delivery performance mart"
- "Add a metric to an existing Gold mart"
- "Create a customer impact summary"
- "Build an inventory risk analytical table"

Even though these operations involve persistent DDL and schemachange migrations, this skill is the correct entry point because it includes business design, grain definition, aggregation logic, scenario validation, and mart-specific checks. The Build phase follows the project's schema-change/migration rules internally.

**Defer to `schema-change`** when the request is primarily a lower-level persistent object change that is not itself a Gold analytical mart (Silver column additions, infrastructure DDL, procedural objects, drops/renames).

## When to Use

Activate this skill when the user asks to:

- Create a new Gold analytical mart, KPI table, summary table, or denormalized analytical object
- Modify an existing Gold mart's structure, measures, or grain
- Add metrics, dimensions, or derived columns to an existing mart
- Build a mart that answers a specific business question from Silver data

Do **not** use this skill for:

- Silver-layer changes (use the `schema-change` skill)
- Ad-hoc analytical queries that don't create persistent objects
- Changes to schemachange configuration or project infrastructure

## Workflow

### Phase 1 — Inspect

1. **Understand the business question(s)** the mart should answer. Ask the user to clarify if the requirement is ambiguous.
2. **Inspect the relevant Silver objects.** Read the version-controlled SQL in `silver/dimensions/`, `silver/facts/`, and `silver/bridges/` for every table that may contribute to the mart. Query Snowflake if needed to confirm current schema and row counts.
3. **Identify relevant synthetic scenarios**, if applicable. Check `validations/silver/scenario_checks.sql` and any scenario ground-truth references to understand which scenarios the mart should preserve or surface.

### Phase 2 — Design

Before creating anything, return the following design specification to the user:

| Element | Detail |
|---|---|
| **Mart name** | Fully qualified object name |
| **Business purpose** | What questions the mart answers |
| **Target grain** | One row per _____ |
| **Business key(s)** | Column(s) that enforce the grain |
| **Silver source tables** | Every Silver table used |
| **Join keys** | Keys used to join sources, with cardinality notes |
| **Measures** | Numeric/additive columns |
| **Derived metrics** | Calculated columns with definitions |
| **Aggregation rules** | Which sources are aggregated and to what level before joining |
| **Expected scenario behavior** | How embedded scenarios should appear in the mart (without hardcoding IDs) |
| **Fan-out risks** | Any many-to-many join risks and how they are mitigated |

**Do not execute anything during the design phase.** Wait for the user to accept or revise the design.

### Phase 3 — Build

After the design is accepted:

1. **Create version-controlled SQL.** Write the mart definition as a SQL file. For views/functions, use a repeatable migration (`R__<description>.sql`). For tables, use a versioned migration (`V<version>__<description>.sql`).
2. **Create the schemachange migration** under `migrations/`. Follow the project's migration conventions (see `AGENTS.md`) for version numbering and file creation.
3. **Aggregate before joining.** When joining multiple fact-like or many-side datasets, aggregate each source to the target grain before joining. Do not join detailed fact tables directly if doing so can create row multiplication.
4. **No hardcoded scenario logic.** Never hardcode scenario IDs, scenario names, expected target entities, or expected outcomes into the mart's transformation logic.
5. **Execute through schemachange**, not through untracked ad-hoc DDL.

### Phase 4 — Validate

Run and report each of the following checks:

| Check | Method |
|---|---|
| **Target grain uniqueness** | `SELECT <business_keys>, COUNT(*) ... HAVING COUNT(*) > 1` — must return 0 rows |
| **NULL / business-key checks** | Verify business key columns have no NULLs |
| **Referential integrity** | Verify FK columns exist in the referenced dimension(s) |
| **Row-count reconciliation** | Compare mart row count against expected count from source grain |
| **Measure reconciliation** | Compare SUM/COUNT of key measures between mart and source |
| **Fan-out detection** | Compare mart row count before and after joins to detect unexpected multiplication |
| **Derived metric validation** | Spot-check derived columns against manual calculation on sample rows |
| **Scenario validation** | Using scenario IDs from ground-truth reference data (validation queries only), confirm that the embedded scenarios produce the expected patterns in the mart |

Scenario-specific IDs and expected values may **only** appear in validation queries, never in the mart's transformation logic.

### Phase 5 — Report

Return:

| Item | Detail |
|---|---|
| **Object created/changed** | Fully qualified name and type |
| **Migration file** | Path and version |
| **Grain** | Target grain and business keys |
| **Source tables** | Silver tables used |
| **Validation results** | Pass/fail for each check in Phase 4 |
| **Scenario validation** | Pass/fail with details |
| **Assumptions** | Any assumptions made during design or build |
| **Unresolved issues** | Any remaining risks, open questions, or follow-up items |
