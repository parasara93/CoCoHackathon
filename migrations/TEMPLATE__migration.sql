-- =============================================================================
-- MIGRATION TEMPLATE (not an executable migration — filename does not match
-- schemachange's V/R/A naming patterns)
-- =============================================================================
--
-- Copy this template when creating a new migration file.
-- Rename to one of:
--   V<major>.<minor>.<patch>__<description>.sql   — versioned (one-time DDL)
--   R__<description>.sql                          — repeatable (views, functions, procs)
--
-- =============================================================================

-- ## Change purpose
-- <Describe why this change is needed>

-- ## Affected object(s)
-- <SUPPLY_CHAIN_DW.SCHEMA.OBJECT_NAME>

-- ## Preconditions
-- <Any objects, data, or state that must exist before this runs>

-- ## DDL
-- <Your CREATE / ALTER / DROP statements here>

-- ## Post-change validation
-- <SQL to verify the change was applied correctly, e.g.:>
-- SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.NEW_TABLE;
-- Run: validations/silver/grain_checks.sql (if Silver-layer change)

-- ## Rollback / manual recovery
-- <Steps to revert if something goes wrong, e.g.:>
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.SILVER.NEW_TABLE;
-- ALTER TABLE ... DROP COLUMN ...;
