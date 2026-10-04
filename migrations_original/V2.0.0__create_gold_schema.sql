-- =============================================================================
-- V2.0.0 — Create Gold Schema
-- =============================================================================
--
-- ## Change purpose
-- Establishes the Gold analytical layer schema for business-facing marts,
-- KPI tables, and denormalized analytical objects.
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD (schema)
--
-- ## Preconditions
-- SUPPLY_CHAIN_DW database must exist.
-- Silver baseline (V1.0.0) must be established.
--
-- ## DDL

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_DW.GOLD;

-- ## Post-change validation
-- SHOW SCHEMAS LIKE 'GOLD' IN DATABASE SUPPLY_CHAIN_DW;

-- ## Rollback / manual recovery
-- DROP SCHEMA IF EXISTS SUPPLY_CHAIN_DW.GOLD;
