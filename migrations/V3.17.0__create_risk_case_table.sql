-- =============================================================================
-- V3.17.0 — Create Risk Case Table
-- =============================================================================
--
-- Change purpose
--   Create a governed case store for agent-initiated supply-chain risk actions.
--
-- Affected object
--   SUPPLY_CHAIN_DW.CONTROL.RISK_CASE
--
-- Grain
--   One row per CASE_ID.
--
-- Design intent
--   Agents do not write directly to business tables.
--   All case creation flows through CONTROL.SP_CREATE_RISK_CASE.
--
-- Preconditions
--   SUPPLY_CHAIN_DW database exists.
--   CONTROL schema exists.
-- =============================================================================

USE DATABASE SUPPLY_CHAIN_DW;
USE SCHEMA CONTROL;


CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_DW.CONTROL.RISK_CASE (
    CASE_ID                 VARCHAR         NOT NULL,

    ENTITY_TYPE             VARCHAR         NOT NULL,
    ENTITY_ID               VARCHAR         NOT NULL,

    RISK_TYPE               VARCHAR         NOT NULL,
    SEVERITY                VARCHAR         NOT NULL,

    SUMMARY                 VARCHAR         NOT NULL,
    RECOMMENDED_ACTION      VARCHAR,

    STATUS                  VARCHAR         NOT NULL DEFAULT 'OPEN',

    SOURCE_AGENT            VARCHAR,
    CREATED_BY              VARCHAR         DEFAULT CURRENT_USER(),

    CREATED_AT              TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT              TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),

    CONSTRAINT PK_RISK_CASE
        PRIMARY KEY (CASE_ID)
);


-- =============================================================================
-- Post-change validation
-- =============================================================================

DESCRIBE TABLE SUPPLY_CHAIN_DW.CONTROL.RISK_CASE;

SELECT COUNT(*) AS RISK_CASE_COUNT
FROM SUPPLY_CHAIN_DW.CONTROL.RISK_CASE;


-- =============================================================================
-- Rollback / manual recovery
-- =============================================================================
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.CONTROL.RISK_CASE;
-- =============================================================================
