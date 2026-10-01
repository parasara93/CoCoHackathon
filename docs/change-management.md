# Change Management

This project uses [schemachange](https://github.com/Snowflake-Labs/schemachange) to manage all persistent Snowflake schema changes through version-controlled migration files.

## Development flow

```text
Requirement
  → CoCo proposes change
  → migration file created under migrations/
  → human reviews Git diff
  → schemachange dry run
  → schemachange deploy
  → validation SQL executed
  → commit / push
```

No persistent Snowflake object should be created or altered directly. Every change flows through a migration file first.

## Migration naming conventions

### Versioned migrations (one-time structural changes)

```text
V<major>.<minor>.<patch>__<description>.sql
```

Examples:
- `V1.1.0__add_supplier_risk_columns.sql`
- `V1.2.0__create_gold_schema.sql`
- `V2.0.0__create_gold_kpi_tables.sql`

Rules:
- Never edit an already-applied versioned migration. Create a new one instead.
- Use for CREATE TABLE, ALTER TABLE, CREATE SCHEMA, DROP, GRANT, etc.

### Repeatable migrations (re-applied when definition changes)

```text
R__<description>.sql
```

Examples:
- `R__create_inventory_risk_view.sql`
- `R__udf_calc_lead_time.sql`

Use only for objects that are intentionally replaced on every change:
- Views (`CREATE OR REPLACE VIEW`)
- Functions (`CREATE OR REPLACE FUNCTION`)
- Stored procedures (`CREATE OR REPLACE PROCEDURE`)

### Always migrations

`A__<description>.sql` scripts are not used in this project unless a specific justified need arises.

### Template

`migrations/TEMPLATE__migration.sql` is a documentation-only template. Its filename does not match any schemachange execution pattern (V/R/A) so it is never executed.

## Baseline strategy

The validated Silver layer (`SUPPLY_CHAIN_DW.SILVER`, 15 objects) was created before schemachange was adopted. The recovered DDL is preserved in:

- `silver/dimensions/*.sql`, `silver/facts/*.sql`, `silver/bridges/*.sql` — source of truth for what was built
- `migrations/V1.0.0__baseline_silver_layer.sql` — no-op marker executed by schemachange

### How the baseline works

`V1.0.0__baseline_silver_layer.sql` contains no destructive DDL — only a `SELECT 1` no-op and documentation comments. When schemachange executes this file during the first deploy, it automatically records version `1.0.0` in the `CHANGE_HISTORY` table. No manual seeding of migration history is needed.

All future migrations start at `V1.1.0` or higher.

### Version numbering going forward

| Range | Purpose |
|---|---|
| V1.0.0 | Silver baseline (no-op, auto-recorded by schemachange) |
| V1.1.0+ | Silver-layer additions/modifications |
| V2.0.0+ | Gold-layer creation and changes |
| V3.0.0+ | Reserved for future layers or major refactors |

## Initialization

### 1. Install schemachange

```bash
pip install schemachange
```

### 2. Configure Snowflake connection

Set the named connection environment variable:

```bash
export SCHEMACHANGE_CONNECTION_NAME=supply_chain
```

The named connection (defined in `~/.snowflake/connections.toml`) must have:
- `database = "SUPPLY_CHAIN_DW"`
- A role with CREATE SCHEMA, CREATE TABLE, and DDL privileges on target schemas

Legacy fallback — individual environment variables:

```bash
export SNOWFLAKE_ACCOUNT=BYMJIUE-FC85049
export SNOWFLAKE_USER=MANCHIRAJUHEMANTH
export SNOWFLAKE_ROLE=<your_role>
export SNOWFLAKE_WAREHOUSE=<your_warehouse>
export SNOWFLAKE_DATABASE=SUPPLY_CHAIN_DW
# Plus one of: SNOWFLAKE_PASSWORD, SNOWFLAKE_PRIVATE_KEY_PATH, SNOWFLAKE_AUTHENTICATOR
```

Or via the legacy connection name variable: `SNOWFLAKE_DEFAULT_CONNECTION_NAME=supply_chain`

### 3. Verify connection

```bash
schemachange verify --config-folder .
```

### 4. Dry run

```bash
schemachange deploy --config-folder . --dry-run
```

This shows which migrations would be applied without executing them. On first run, it will also indicate that the `SCHEMACHANGE` schema and `CHANGE_HISTORY` table will be created (via `create-change-history-table: true`).

### 5. Deploy migrations

```bash
schemachange deploy --config-folder .
```

On first run this will:
1. Create `SUPPLY_CHAIN_DW.SCHEMACHANGE` schema and `CHANGE_HISTORY` table automatically
2. Execute `V1.0.0` (no-op baseline marker) and record it in `CHANGE_HISTORY`
3. Apply any subsequent versioned/repeatable migrations

### 6. Verify CHANGE_HISTORY

```sql
SELECT VERSION, DESCRIPTION, SCRIPT, STATUS, INSTALLED_ON
FROM SUPPLY_CHAIN_DW.SCHEMACHANGE.CHANGE_HISTORY
ORDER BY INSTALLED_ON;
```

Confirm that `V1.0.0__baseline_silver_layer.sql` appears with status `Success`.

## Validation

After any Silver-layer migration, run the validation suite:

```sql
-- In order:
@validations/silver/grain_checks.sql
@validations/silver/dimension_key_checks.sql
@validations/silver/referential_integrity.sql
@validations/silver/derived_column_checks.sql
@validations/silver/scenario_checks.sql
```

## Files overview

| File | Purpose |
|---|---|
| `schemachange-config.yml` | schemachange configuration (config v2) |
| `migrations/V1.0.0__baseline_silver_layer.sql` | No-op baseline marker for Silver layer |
| `migrations/TEMPLATE__migration.sql` | Template for new migrations (not executable) |
| `silver/**/*.sql` | Recovered Silver DDL (source of truth for what was built) |
| `validations/silver/*.sql` | Post-change validation queries |
| `docs/change-management.md` | This document |
