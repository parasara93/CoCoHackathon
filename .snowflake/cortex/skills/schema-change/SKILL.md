---
name: schema-change
description: Workflow for persistent Snowflake DDL/object-definition changes, including initial environment/bootstrap creation in a new account, managed through schemachange migrations. Use when creating, altering, replacing, or dropping tables, views, functions, procedures, streams, tasks, or any tracked DDL. Not required for pure data loading, COPY INTO, historical replay, MERGE execution, audit logging, reconciliation, or validations when no object definitions change.
---

# Schema Change

Repeatable workflow for persistent Snowflake schema and object changes, executed through version-controlled schemachange migrations.

See `AGENTS.md` for permanent project rules (deduplication keys, derived columns, excluded RAW tables, validation suite, version ranges, migration conventions).

## Skill Precedence

This skill handles **lower-level persistent DDL** that is not itself a Gold analytical mart.

**If the request is primarily about creating, modifying, or extending a Gold analytical mart** (KPI mart, risk mart, control-tower mart, supplier summary, delivery performance mart, or similar business-facing analytical output), use the `build-and-validate-mart` skill instead — even though those operations also involve persistent DDL and schemachange. The mart skill includes business design, grain definition, aggregation logic, scenario validation, and mart-specific checks that this skill does not cover.

**Use this skill when** the request is primarily about:

- Initial environment/bootstrap creation (databases, schemas, storage integrations, stages, file formats, audit/control tables) in a new or empty Snowflake account
- Silver-layer structural changes (add/alter/drop columns, new Silver tables)
- Infrastructure objects (schemas, grants, stages, file formats)
- Procedural objects (functions, procedures, streams, tasks)
- Dropping or renaming existing objects
- Any persistent DDL that is not a Gold analytical mart

## When to Use

Activate this skill when the user asks to:

- Create a persistent table, view, function, procedure, stream, or task
- Alter an existing persistent object (add/drop/rename columns, change types, modify constraints)
- Replace an existing object definition
- Drop a persistent object
- Change schema-level properties or grants
- Make any Snowflake change that should be tracked through schemachange

Do **not** use this skill for:

- Ad-hoc analytical queries (SELECT only, no persistent changes)
- Validation-only runs (use the validation SQL directly)
- Changes to the schemachange configuration itself
- Gold analytical mart creation or modification (use `build-and-validate-mart`)
- Pure data loading (COPY INTO, PUT, batch inserts) that does not change object definitions
- Historical replay or CDC execution (MERGE, upsert) that operates on existing objects
- Audit logging, reconciliation queries, or validation execution when no DDL is involved

If a CDC or replay task requires creating or altering tables, streams, tasks, procedures, stages, file formats, or control/audit objects, use this skill for those DDL changes only. The subsequent data loading, MERGE execution, and validation runs are DML/orchestration work and do not require this skill.

For mixed DDL + DML tasks, apply this skill only to the DDL/object-definition portion. Subsequent operations such as COPY INTO, historical data loading, replay, MERGE execution, reconciliation, and validation remain outside the schema-change workflow unless they themselves require an object-definition change.

## Workflow

### Step 1 — Inspect current state

- Read the relevant version-controlled SQL file(s) under `silver/`, `migrations/`, or other project directories.
- Query the current Snowflake object definition if needed (`DESCRIBE TABLE`, `GET_DDL`, `SHOW COLUMNS`, etc.).
- Identify the object's current grain, keys, dependencies, and downstream consumers.
- Inspect existing migration files in `migrations/` to understand the current version sequence.
- When available, query `SUPPLY_CHAIN_DW.SCHEMACHANGE.CHANGE_HISTORY` to confirm which migrations have been applied and detect any drift between Git and Snowflake state.

### Step 2 — State the intended change

Return to the user:

- Object name and type
- What will change (columns, types, logic, new object, etc.)
- Why the change is needed

### Step 3 — Impact assessment

Before writing the migration, check whether the change could affect:

- **Grain** — does the change alter the primary/composite key or introduce duplication?
- **Joins / fan-out** — could the change cause row multiplication in downstream queries or marts?
- **Dependencies** — are other objects (views, procedures, tasks, marts) referencing this object?
- **Downstream objects** — will downstream consumers break or produce incorrect results?
- **Data types** — could type changes cause implicit casting, precision loss, or NULL behavior changes?
- **Existing validations** — do any validation SQL files need updating to cover the change?
- **Destructive vs. rebuild** — is this an ALTER or a full CREATE OR REPLACE? If rebuild, note that downstream consumers may see a brief interruption.

Report findings to the user before proceeding.

### Step 4 — Determine migration version

- Check existing files in `migrations/` to find the current highest version.
- Assign the next valid version following the project's `V<major>.<minor>.<patch>` convention.
- Use `R__<description>.sql` only for views, functions, or procedures that are intentionally reapplied.

### Step 5 — Create the migration file

- Create a new file under `migrations/` with the correct naming convention.
- Include header comments: change purpose, affected object, preconditions.
- Write the DDL.
- Include post-change validation notes.
- Include rollback/recovery notes where practical.

### Step 6 — Immutability rule

Never modify an already-applied versioned migration. If a previous migration needs correction, create a new migration that applies the fix.

### Step 7 — Show migration before execution

Present the complete migration file contents and a summary diff to the user. Wait for acceptance before executing.

### Step 8 — Validate migration logic

Review the SQL for:

- Syntax correctness
- Correct schema/database references
- Alignment with `AGENTS.md` rules (dedup keys, derived column definitions, excluded tables)
- No hardcoded scenario IDs in transformation logic

### Step 9 — Execution guardrails

**Critical rule:** Never execute a persistent schema/object change outside schemachange. Never manually write to `SUPPLY_CHAIN_DW.SCHEMACHANGE.CHANGE_HISTORY`.

**If schemachange CLI is available:**

1. Run dry-run first:
   ```bash
   schemachange deploy --config-folder . --dry-run
   ```
2. Inspect pending migrations. Check for:
   - Unexpected older versions still pending
   - Checksum drift warnings (applied migration files modified on disk)
   - Git and `CHANGE_HISTORY` out of sync
3. Do not continue blindly if history and Git are out of sync. Report the discrepancy and wait for user guidance.
4. If dry-run is clean, execute:
   ```bash
   schemachange deploy --config-folder .
   ```

**If schemachange CLI is NOT available in the current environment:**

1. Create the migration file under `migrations/`.
2. Create or update the relevant validation SQL under `validations/`.
3. **Do not execute the migration SQL directly** through `snowflake_sql_execute`, ad-hoc SQL tools, or any other mechanism.
4. **Stop** and report:
   > Migration prepared; execution pending through schemachange.
5. The user or CI/CD pipeline executes externally through a working schemachange environment.

### Step 10 — Post-deploy verification

After execution through schemachange:

1. **Verify migration recorded:** Query `SUPPLY_CHAIN_DW.SCHEMACHANGE.CHANGE_HISTORY` to confirm the new version appears with `Status = 'Success'`.
2. **Verify object state:** Confirm the target object exists in the expected schema with the expected column count / structure.
3. **Run validation SQL:** Execute the relevant validation queries from `validations/silver/` or `validations/gold/`:
   - Silver changes: `grain_checks.sql`, `dimension_key_checks.sql`, `referential_integrity.sql`, `derived_column_checks.sql`, `scenario_checks.sql`
   - Gold changes: the mart-specific validation file (e.g., `validations/gold/mart_supplier_risk_checks.sql`)
   - Run only the checks relevant to the changed object(s).
4. Report PASS/FAIL for each check and any discrepancies.

### Step 11 — Report

Always return:

- Migration version and file path
- Object(s) changed (fully qualified names)
- Deployment method (`schemachange` or `pending — not yet executed`)
- schemachange history status (confirmed in `CHANGE_HISTORY` or pending)
- Validation results (PASS/FAIL per check)
- Assumptions or issues
- Any pending manual action required

## Rules

- Never treat chat history as the implementation source of truth. The validated state is defined by Snowflake objects and version-controlled SQL.
- Do not silently fix unrelated problems discovered during the change. Report them separately.
- **Do not create fake migration history or manually insert, update, or delete rows in `SUPPLY_CHAIN_DW.SCHEMACHANGE.CHANGE_HISTORY`.** Only schemachange itself may write to this table.
- **Do not bypass schemachange** by executing migration SQL directly for convenience, even if schemachange is slow or unavailable. Prepare the file and stop.
- Respect the existing baseline migration strategy (`V1.0.0` is the Silver baseline no-op).
- The authoritative change-management state is migration files in Git **plus** `SUPPLY_CHAIN_DW.SCHEMACHANGE.CHANGE_HISTORY`. Both must agree.
