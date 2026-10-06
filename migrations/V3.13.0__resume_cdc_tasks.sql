-- =============================================================================
-- V3.13.0 — Resume CDC Tasks
-- =============================================================================
-- Purpose:
--   Activate the 8 RAW -> SILVER triggered CDC tasks created in V3.11.0.
--
-- Preconditions:
--   * V3.8.0 streams exist.
--   * V3.9.0 CDC_STREAM_RUN_LOG exists.
--   * V3.10.0 procedures exist.
--   * V3.11.0 tasks exist.
--   * V3.12.0 validation completed successfully.
--   * Historical RAW load and Silver baseline are complete.
--
-- Important:
--   Triggered tasks can start processing as soon as their WHEN condition
--   evaluates TRUE after they are resumed.
-- =============================================================================

USE DATABASE SUPPLY_CHAIN_DW;
USE SCHEMA CONTROL;


-- =============================================================================
-- 1. Resume direct single-stream CDC tasks
-- =============================================================================

ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_INVENTORY_SNAPSHOT
    RESUME;

ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_BRIDGE_SUPPLIER_PART
    RESUME;

ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SUPPLIER_PERFORMANCE
    RESUME;

ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT
    RESUME;

ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT_LINE
    RESUME;

ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT_EVENT
    RESUME;

ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_VEHICLE_TELEMETRY
    RESUME;


-- =============================================================================
-- 2. Resume dual-stream order-line CDC task
-- =============================================================================

ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_ORDER_LINE
    RESUME;


-- =============================================================================
-- 3. Post-activation verification
-- =============================================================================
-- Expected:
--   8 TASK_CDC_* tasks with STATE = started.
-- =============================================================================

SHOW TASKS LIKE 'TASK_CDC_%'
    IN SCHEMA SUPPLY_CHAIN_DW.CONTROL;


-- =============================================================================
-- Optional operational check after an incremental RAW load
-- =============================================================================
-- SELECT *
-- FROM SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
-- ORDER BY STARTED_AT DESC;
--
-- Do not treat an empty run log immediately after task activation as failure.
-- A task only executes when its SYSTEM$STREAM_HAS_DATA condition is TRUE.
-- =============================================================================


-- =============================================================================
-- Manual emergency suspension commands
-- =============================================================================
-- ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_INVENTORY_SNAPSHOT SUSPEND;
-- ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_BRIDGE_SUPPLIER_PART SUSPEND;
-- ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SUPPLIER_PERFORMANCE SUSPEND;
-- ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT SUSPEND;
-- ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT_LINE SUSPEND;
-- ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_SHIPMENT_EVENT SUSPEND;
-- ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_VEHICLE_TELEMETRY SUSPEND;
-- ALTER TASK SUPPLY_CHAIN_DW.CONTROL.TASK_CDC_FACT_ORDER_LINE SUSPEND;


-- =============================================================================
-- End V3.13.0
-- =============================================================================
