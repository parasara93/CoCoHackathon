-- =============================================================================
-- V3.12.0 — Validate CDC Objects
-- =============================================================================
-- Purpose:
--   Fail fast if any CDC stream, procedure, or task required by the CDC design
--   is missing after V3.8.0 through V3.11.0.
--
-- Notes:
--   * This migration does NOT resume tasks.
--   * DESCRIBE statements intentionally fail the migration if an object is
--     missing or inaccessible.
--   * SYSTEM$STREAM_HAS_DATA checks confirm all stream references resolve.
--     TRUE/FALSE is informational; either value is valid.
-- =============================================================================

USE DATABASE SUPPLY_CHAIN_DW;
USE SCHEMA CONTROL;


-- =============================================================================
-- 1. Validate 9 RAW CDC streams
-- =============================================================================

DESCRIBE STREAM SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDERS;
DESCRIBE STREAM SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDER_LINES;
DESCRIBE STREAM SUPPLY_CHAIN_DW.RAW.STRM_RAW_INVENTORY;
DESCRIBE STREAM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SUPPLIER_PARTS;
DESCRIBE STREAM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SUPPLIER_PERFORMANCE;
DESCRIBE STREAM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENTS;
DESCRIBE STREAM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENT_LINES;
DESCRIBE STREAM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENT_EVENTS;
DESCRIBE STREAM SUPPLY_CHAIN_DW.RAW.STRM_RAW_VEHICLE_TELEMETRY;


-- Informational backlog check.
-- FALSE means no unconsumed rows are currently waiting.
-- TRUE means the stream currently contains rows to process.
SELECT
    SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDERS'
    ) AS ORDERS_HAS_DATA,

    SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDER_LINES'
    ) AS ORDER_LINES_HAS_DATA,

    SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_INVENTORY'
    ) AS INVENTORY_HAS_DATA,

    SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_SUPPLIER_PARTS'
    ) AS SUPPLIER_PARTS_HAS_DATA,

    SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_SUPPLIER_PERFORMANCE'
    ) AS SUPPLIER_PERFORMANCE_HAS_DATA,

    SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENTS'
    ) AS SHIPMENTS_HAS_DATA,

    SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENT_LINES'
    ) AS SHIPMENT_LINES_HAS_DATA,

    SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENT_EVENTS'
    ) AS SHIPMENT_EVENTS_HAS_DATA,

    SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_VEHICLE_TELEMETRY'
    ) AS VEHICLE_TELEMETRY_HAS_DATA;


-- =============================================================================
-- 2. Validate 8 CDC procedures
-- =============================================================================

DESCRIBE PROCEDURE
    SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_INVENTORY_SNAPSHOT();

DESCRIBE PROCEDURE
    SUPPLY_CHAIN_DW.CONTROL.SP_CDC_BRIDGE_SUPPLIER_PART();

DESCRIBE PROCEDURE
    SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SUPPLIER_PERFORMANCE();

DESCRIBE PROCEDURE
    SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SHIPMENT();

DESCRIBE PROCEDURE
    SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SHIPMENT_LINE();

DESCRIBE PROCEDURE
    SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SHIPMENT_EVENT();

DESCRIBE PROCEDURE
    SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_VEHICLE_TELEMETRY();

DESCRIBE PROCEDURE
    SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_ORDER_LINE();


-- =============================================================================
-- 3. Validate 8 CDC tasks
-- =============================================================================

DESCRIBE TASK
    SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_INVENTORY_SNAPSHOT;

DESCRIBE TASK
    SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_BRIDGE_SUPPLIER_PART;

DESCRIBE TASK
    SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SUPPLIER_PERFORMANCE;

DESCRIBE TASK
    SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT;

DESCRIBE TASK
    SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT_LINE;

DESCRIBE TASK
    SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT_EVENT;

DESCRIBE TASK
    SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_VEHICLE_TELEMETRY;

DESCRIBE TASK
    SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_ORDER_LINE;


-- =============================================================================
-- 4. Human-readable task-state check
-- =============================================================================
-- Expected before V3.13.0:
--   8 TASK_CDC_* tasks, all STATE = suspended.
--
-- SHOW TASKS exposes STATE as "started" or "suspended".
-- =============================================================================

SHOW TASKS LIKE 'TASK_CDC_%'
    IN SCHEMA SUPPLY_CHAIN_DW.CONTROL;


-- =============================================================================
-- 5. Validate CDC run-log table
-- =============================================================================

DESCRIBE TABLE SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG;


-- =============================================================================
-- End V3.12.0
-- =============================================================================
