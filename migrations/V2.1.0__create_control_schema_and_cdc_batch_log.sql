-- =============================================================================
-- V2.1.0 — Create CONTROL Schema and CDC_BATCH_LOG Table
-- =============================================================================
--
-- Purpose:
--   Creates the CONTROL schema for operational/audit objects and the
--   CDC_BATCH_LOG table for tracking incremental batch processing status.
--
-- Objects created:
--   Schema: SUPPLY_CHAIN_DW.CONTROL
--   Table:  SUPPLY_CHAIN_DW.CONTROL.CDC_BATCH_LOG
--
-- Grain:
--   One row per (LOAD_BATCH_ID, TABLE_NAME, PROCESSING_STAGE).
--   This allows tracking RAW load and each Silver target independently.
--
-- Preconditions:
--   SUPPLY_CHAIN_DW database must exist.
--
-- Rollback:
--   DROP SCHEMA IF EXISTS SUPPLY_CHAIN_DW.CONTROL CASCADE;
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_DW.CONTROL;

CREATE TABLE SUPPLY_CHAIN_DW.CONTROL.CDC_BATCH_LOG (
    LOAD_BATCH_ID       VARCHAR(30)      NOT NULL,
    SOURCE_BATCH_TS     TIMESTAMP_NTZ    NOT NULL,
    TABLE_NAME          VARCHAR(50)      NOT NULL,
    PROCESSING_STAGE    VARCHAR(20)      NOT NULL,
    STATUS              VARCHAR(20)      NOT NULL,
    ROWS_LOADED         NUMBER,
    ROWS_INSERTED       NUMBER,
    ROWS_UPDATED        NUMBER,
    ROWS_SKIPPED        NUMBER,
    ERROR_MESSAGE       VARCHAR(2000),
    STARTED_AT          TIMESTAMP_NTZ    NOT NULL,
    COMPLETED_AT        TIMESTAMP_NTZ
);
