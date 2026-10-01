---
name: schema-change
description: Workflow for any persistent Snowflake schema or object change managed through schemachange migrations. Use when creating, altering, replacing, or dropping tables, views, functions, procedures, streams, tasks, or any tracked DDL.
---

# Schema Change

Repeatable workflow for persistent Snowflake schema and object changes, executed through version-controlled schemachange migrations.

See `AGENTS.md` for permanent project rules (deduplication keys, derived columns, excluded RAW tables, validation suite, version ranges, migration conventions).

## Skill Precedence

This skill handles **lower-level persistent DDL** that is not itself a Gold analytical mart.

**If the request is primarily about creating, modifying, or extending a Gold analytical mart** (KPI mart, risk mart, control-tower mart, supplier summary, delivery performance mart, or similar business-facing analytical output), use the `build-and-validate-mart` skill instead — even though those operations also involve persistent DDL and schemachange. The mart skill includes business design, grain definition, aggregation logic, scenario validation, and mart-specific checks that this skill does not cover.

**Use this skill when** the request is primarily about:

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

## Workflow

### Step 1 — Inspect current state

- Read the relevant version-controlled SQL file(s) under `silver/`, `migrations/`, or other project directories.
- Query the current Snowflake object definition if needed (`DESCRIBE TABLE`, `GET_DDL`, `SHOW COLUMNS`, etc.).
- Identify the object's current grain, keys, dependencies, and downstream consumers.

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

### Step 9 — Execute through schemachange

Run the migration through schemachange, not through untracked ad-hoc DDL:

```bash
schemachange deploy --config-folder . --dry-run   # preview
schemachange deploy --config-folder .              # apply
```

### Step 10 — Run validation SQL

After execution, run the relevant validation queries from `validations/silver/`:

- `grain_checks.sql`
- `dimension_key_checks.sql`
- `referential_integrity.sql`
- `derived_column_checks.sql`
- `scenario_checks.sql`

Run only the checks relevant to the changed object(s).

### Step 11 — Report

Return:

- Migration file created (path and version)
- Objects changed
- Validation results (pass/fail per check)
- Any remaining risks, issues, or follow-up items

## Rules

- Never treat chat history as the implementation source of truth. The validated state is defined by Snowflake objects and version-controlled SQL.
- Do not silently fix unrelated problems discovered during the change. Report them separately.
- Do not create fake migration history or manually insert rows into `CHANGE_HISTORY`.
- Respect the existing baseline migration strategy (`V1.0.0` is the Silver baseline no-op).
