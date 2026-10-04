-- =============================================================================
-- V3.0.0 -- Create GOLD schema
-- =============================================================================
--
-- ## Change purpose
-- Create the Gold analytical mart schema for the Resilient Supply Chain
-- Control Tower. Prerequisite for all Gold marts (V3.1.0+).
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD (schema)
--
-- ## Preconditions
-- SUPPLY_CHAIN_DW database must exist.
-- V2.1.0 (CONTROL schema + CDC_BATCH_LOG) must be applied.
--
-- ## DDL

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_DW.GOLD;

-- ## Post-change validation
-- SHOW SCHEMAS IN DATABASE SUPPLY_CHAIN_DW should list GOLD.

-- ## Rollback / manual recovery
-- DROP SCHEMA IF EXISTS SUPPLY_CHAIN_DW.GOLD CASCADE;
