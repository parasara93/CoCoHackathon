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

## Migration chain history

### Original partial chain (archived)

The original migration chain (V1.0.0–V2.7.0, plus V3.0.0) was written for a Snowflake account where Silver tables already existed before schemachange was adopted. That chain is **not a valid deploy-from-zero sequence** because:

- V1.0.0 was a no-op marker that assumed Silver already existed.
- V2.1.0+ Gold mart migrations referenced Silver tables via `SELECT ... FROM SUPPLY_CHAIN_DW.SILVER.*`.
- V3.0.0 contained an environment-specific AWS storage integration.

These files are preserved in `migrations_original/` for reference. They must not be placed back into `migrations/` without adaptation.

### Current canonical chain (fresh-account rebuild)

The active `migrations/` directory contains the canonical fresh-account deployment path. Every migration creates its objects from scratch in dependency order — no migration references objects that have not been created by an earlier migration.

### Version numbering

| Range | Purpose |
|---|---|
| V1.0.0 | RAW schema and tables |
| V1.1.0+ | RAW-layer infrastructure (file formats, stages) |
| V2.0.0+ | Silver schema and tables |
| V3.0.0+ | Gold schema, marts, validation objects |

### Environment-specific objects

The AWS S3 storage integration (`SUPPLY_CHAIN_S3_INTEGRATION`) depends on an environment-specific IAM role ARN and requires a manual AWS trust-policy handshake. It is treated as environment/bootstrap configuration rather than portable project migration DDL. It must be created outside the versioned migration chain before V1.1.0 (stage creation) can run.

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
1. Create the `CHANGE_HISTORY` table automatically (the `SUPPLY_CHAIN_DW` database and `SCHEMACHANGE` schema must already exist — see bootstrap prerequisites below)
2. Execute `V1.0.0` (create RAW schema and tables) and record it in `CHANGE_HISTORY`
3. Apply any subsequent versioned/repeatable migrations

### Bootstrap prerequisites

Schemachange 4.3.3 requires the target database and schema to exist before it can connect. These must be created manually before the first deploy:

```sql
CREATE DATABASE IF NOT EXISTS SUPPLY_CHAIN_DW;
CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_DW.SCHEMACHANGE;
```

### 6. Verify CHANGE_HISTORY

```sql
SELECT VERSION, DESCRIPTION, SCRIPT, STATUS, INSTALLED_ON
FROM SUPPLY_CHAIN_DW.SCHEMACHANGE.CHANGE_HISTORY
ORDER BY INSTALLED_ON;
```

Confirm that `V1.0.0__create_raw_schema_and_tables.sql` appears with status `Success`.

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
| `migrations/V1.0.0__create_raw_schema_and_tables.sql` | Create RAW schema and 15 operational tables |
| `migrations/TEMPLATE__migration.sql` | Template for new migrations (not executable) |
| `migrations_original/` | Archived original migration chain (reference only) |
| `silver/**/*.sql` | Recovered Silver DDL (source of truth for what was built) |
| `validations/silver/*.sql` | Post-change validation queries |
| `docs/change-management.md` | This document |
