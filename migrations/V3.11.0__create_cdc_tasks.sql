-- =============================================================================
-- V3.11.0 — Create RAW -> SILVER CDC Tasks
-- =============================================================================
-- Creates one triggered task per CDC procedure created in V3.10.0.
--
-- Important:
--   * Tasks are created SUSPENDED by default.
--   * Do not RESUME them in this migration.
--   * Resume only after:
--       1. historical RAW load is complete,
--       2. Silver baseline is built,
--       3. V3.8.0 streams exist,
--       4. V3.9.0 CDC log exists,
--       5. V3.10.0 procedures are validated.
--
-- Requires:
--   V3.8.0 RAW CDC streams
--   V3.9.0 CONTROL.CDC_STREAM_RUN_LOG
--   V3.10.0 CDC procedures
-- =============================================================================

USE DATABASE SUPPLY_CHAIN_DW;
USE SCHEMA CONTROL;


-- =============================================================================
-- 1. INVENTORY -> FACT_INVENTORY_SNAPSHOT
-- =============================================================================

CREATE OR REPLACE TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_INVENTORY_SNAPSHOT
    WAREHOUSE = COMPUTE_WH
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_INVENTORY'
    )
AS
    CALL SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_INVENTORY_SNAPSHOT();


-- =============================================================================
-- 2. SUPPLIER_PARTS -> BRIDGE_SUPPLIER_PART
-- =============================================================================

CREATE OR REPLACE TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_BRIDGE_SUPPLIER_PART
    WAREHOUSE = COMPUTE_WH
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_SUPPLIER_PARTS'
    )
AS
    CALL SUPPLY_CHAIN_DW.CONTROL.SP_CDC_BRIDGE_SUPPLIER_PART();


-- =============================================================================
-- 3. SUPPLIER_PERFORMANCE -> FACT_SUPPLIER_PERFORMANCE
-- =============================================================================

CREATE OR REPLACE TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SUPPLIER_PERFORMANCE
    WAREHOUSE = COMPUTE_WH
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_SUPPLIER_PERFORMANCE'
    )
AS
    CALL SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SUPPLIER_PERFORMANCE();


-- =============================================================================
-- 4. SHIPMENTS -> FACT_SHIPMENT
-- =============================================================================

CREATE OR REPLACE TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT
    WAREHOUSE = COMPUTE_WH
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENTS'
    )
AS
    CALL SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SHIPMENT();


-- =============================================================================
-- 5. SHIPMENT_LINES -> FACT_SHIPMENT_LINE
-- =============================================================================

CREATE OR REPLACE TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT_LINE
    WAREHOUSE = COMPUTE_WH
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENT_LINES'
    )
AS
    CALL SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SHIPMENT_LINE();


-- =============================================================================
-- 6. SHIPMENT_EVENTS -> FACT_SHIPMENT_EVENT
-- =============================================================================

CREATE OR REPLACE TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT_EVENT
    WAREHOUSE = COMPUTE_WH
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENT_EVENTS'
    )
AS
    CALL SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SHIPMENT_EVENT();


-- =============================================================================
-- 7. VEHICLE_TELEMETRY -> FACT_VEHICLE_TELEMETRY
-- =============================================================================

CREATE OR REPLACE TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_VEHICLE_TELEMETRY
    WAREHOUSE = COMPUTE_WH
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SUPPLY_CHAIN_DW.RAW.STRM_RAW_VEHICLE_TELEMETRY'
    )
AS
    CALL SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_VEHICLE_TELEMETRY();


-- =============================================================================
-- 8. ORDERS + ORDER_LINES -> FACT_ORDER_LINE
-- =============================================================================
-- Either RAW stream can trigger the same dual-source processor.
-- The procedure reads BOTH streams and recomputes affected order lines using
-- the latest versions from full RAW.
-- =============================================================================

CREATE OR REPLACE TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_ORDER_LINE
    WAREHOUSE = COMPUTE_WH
    WHEN (
        SYSTEM$STREAM_HAS_DATA(
            'SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDERS'
        )
        OR
        SYSTEM$STREAM_HAS_DATA(
            'SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDER_LINES'
        )
    )
AS
    CALL SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_ORDER_LINE();


-- =============================================================================
-- Post-deployment checks
-- =============================================================================
-- SHOW TASKS IN SCHEMA SUPPLY_CHAIN_DW.CONTROL;
--
-- Expected: all 8 TASK_CDC_* tasks exist and remain SUSPENDED.
--
-- Do NOT resume here.
-- A later activation migration can explicitly RESUME all 8 tasks.
-- =============================================================================
