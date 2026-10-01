-- =============================================================================
-- V2.2.0 — Create Validation Schema and Scenario Ground-Truth Tables
-- =============================================================================
--
-- ## Change purpose
-- Creates the VALIDATION schema and two tables for scenario ground-truth data:
-- 1. SCENARIO_GROUND_TRUTH — preserved CSV at one row per scenario
-- 2. SCENARIO_AFFECTED_ENTITY — normalized entity rows for mart validation
--
-- These are validation-only tables. They must NEVER be joined into
-- production RAW → SILVER → GOLD transformations.
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.VALIDATION (schema)
-- SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_GROUND_TRUTH (table)
-- SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY (table)
--
-- ## Preconditions
-- V2.0.0 (GOLD schema) and V2.1.0 (MART_CUSTOMER_IMPACT) applied.
-- Scenario ground-truth CSV loaded via stage.
--
-- ## DDL

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_DW.VALIDATION;

-- Preserved ground-truth table: one row per scenario, CSV fields intact
CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_GROUND_TRUTH (
    SCENARIO_ID                 VARCHAR        NOT NULL,
    SCENARIO_TYPE               VARCHAR        NOT NULL,
    SCENARIO_START_TIMESTAMP    TIMESTAMP_NTZ  NOT NULL,
    SCENARIO_END_TIMESTAMP      TIMESTAMP_NTZ  NOT NULL,
    PRIMARY_ENTITY_TYPE         VARCHAR        NOT NULL,
    PRIMARY_ENTITY_ID           VARCHAR        NOT NULL,
    AFFECTED_SUPPLIER_IDS       VARCHAR,
    AFFECTED_PART_IDS           VARCHAR,
    AFFECTED_PLANT_IDS          VARCHAR,
    AFFECTED_ROUTE_IDS          VARCHAR,
    AFFECTED_SHIPMENT_IDS       VARCHAR,
    AFFECTED_ORDER_IDS          VARCHAR,
    EXPECTED_BUSINESS_EFFECT    VARCHAR        NOT NULL,
    LOADED_AT                   TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
    SOURCE_FILE_NAME            VARCHAR        DEFAULT 'scenario_ground_truth.csv'
);

-- Normalized affected-entity table: one row per (scenario, entity_type, entity_id)
CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY (
    SCENARIO_ID                 VARCHAR        NOT NULL,
    SCENARIO_TYPE               VARCHAR        NOT NULL,
    SCENARIO_START_TIMESTAMP    TIMESTAMP_NTZ  NOT NULL,
    SCENARIO_END_TIMESTAMP      TIMESTAMP_NTZ  NOT NULL,
    ENTITY_TYPE                 VARCHAR        NOT NULL,
    ENTITY_ID                   VARCHAR        NOT NULL,
    IS_PRIMARY_ENTITY           BOOLEAN        NOT NULL,
    EXPECTED_BUSINESS_EFFECT    VARCHAR        NOT NULL
);

-- ## Post-change validation
-- SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_GROUND_TRUTH;
-- SELECT SCENARIO_ID, ENTITY_TYPE, ENTITY_ID, COUNT(*)
--   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
--   GROUP BY 1,2,3 HAVING COUNT(*) > 1;  -- must return 0

-- ## Rollback / manual recovery
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY;
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_GROUND_TRUTH;
-- DROP SCHEMA IF EXISTS SUPPLY_CHAIN_DW.VALIDATION;
