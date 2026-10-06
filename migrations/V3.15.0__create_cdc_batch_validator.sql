-- =============================================================================
-- V3.15.0 — Create CDC End-to-End Batch Validator
-- =============================================================================
-- Purpose:
--   Validate one controlled incremental batch after:
--
--       S3 -> RAW -> Stream -> Task -> CDC Procedure -> Silver -> Run Log
--
-- This migration creates the validator only. It does NOT load a batch.
--
-- Suggested manual test:
--
--   CALL SUPPLY_CHAIN_DW.CONTROL.SP_LOAD_INCREMENTAL_RAW_BATCH(
--       '20260924_0630'
--   );
--
--   -- allow the triggered tasks to run
--
--   CALL SUPPLY_CHAIN_DW.CONTROL.SP_VALIDATE_CDC_BATCH(
--       '20260924_0630'
--   );
--
-- PASS criteria:
--   * RAW_ROWS > 0
--   * FAILED_PIPELINES = 0
--   * SUCCESSFUL_PIPELINES >= EXPECTED_PIPELINES
--   * SILVER_DUPLICATE_GROUPS = 0
--
-- Notes:
--   EXPECTED_PIPELINES is derived from which RAW tables actually received rows
--   for the supplied LOAD_BATCH_ID. This allows:
--     * sparse SHIPMENT_LINES
--     * IoT-only hourly batches
--     * ERP/Supplier/Logistics batches
-- =============================================================================

USE DATABASE SUPPLY_CHAIN_DW;
USE SCHEMA CONTROL;


CREATE OR REPLACE PROCEDURE
SUPPLY_CHAIN_DW.CONTROL.SP_VALIDATE_CDC_BATCH(P_BATCH_SUFFIX VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_BATCH_ID VARCHAR;

    V_ORDERS_ROWS               NUMBER DEFAULT 0;
    V_ORDER_LINES_ROWS          NUMBER DEFAULT 0;
    V_INVENTORY_ROWS            NUMBER DEFAULT 0;
    V_SUPPLIER_PARTS_ROWS       NUMBER DEFAULT 0;
    V_SUPPLIER_PERF_ROWS        NUMBER DEFAULT 0;
    V_SHIPMENTS_ROWS            NUMBER DEFAULT 0;
    V_SHIPMENT_LINES_ROWS       NUMBER DEFAULT 0;
    V_SHIPMENT_EVENTS_ROWS      NUMBER DEFAULT 0;
    V_TELEMETRY_ROWS            NUMBER DEFAULT 0;

    V_RAW_ROWS                  NUMBER DEFAULT 0;
    V_EXPECTED_PIPELINES        NUMBER DEFAULT 0;
    V_SUCCESSFUL_PIPELINES      NUMBER DEFAULT 0;
    V_FAILED_PIPELINES          NUMBER DEFAULT 0;
    V_DUPLICATE_GROUPS          NUMBER DEFAULT 0;

    V_PASS                      BOOLEAN DEFAULT FALSE;
BEGIN

    IF (
        P_BATCH_SUFFIX IS NULL
        OR NOT REGEXP_LIKE(P_BATCH_SUFFIX, '^[0-9]{8}_[0-9]{4}$')
    ) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'INVALID_INPUT',
            'message',
            'Expected batch suffix YYYYMMDD_HHMM, e.g. 20260924_0630'
        );
    END IF;

    V_BATCH_ID := 'INCR_' || P_BATCH_SUFFIX;


    -- =========================================================================
    -- 1. Confirm the selected batch landed in RAW
    -- =========================================================================

    SELECT COUNT(*) INTO :V_ORDERS_ROWS
    FROM SUPPLY_CHAIN_DW.RAW.ORDERS
    WHERE LOAD_BATCH_ID = :V_BATCH_ID;

    SELECT COUNT(*) INTO :V_ORDER_LINES_ROWS
    FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES
    WHERE LOAD_BATCH_ID = :V_BATCH_ID;

    SELECT COUNT(*) INTO :V_INVENTORY_ROWS
    FROM SUPPLY_CHAIN_DW.RAW.INVENTORY
    WHERE LOAD_BATCH_ID = :V_BATCH_ID;

    SELECT COUNT(*) INTO :V_SUPPLIER_PARTS_ROWS
    FROM SUPPLY_CHAIN_DW.RAW.SUPPLIER_PARTS
    WHERE LOAD_BATCH_ID = :V_BATCH_ID;

    SELECT COUNT(*) INTO :V_SUPPLIER_PERF_ROWS
    FROM SUPPLY_CHAIN_DW.RAW.SUPPLIER_PERFORMANCE
    WHERE LOAD_BATCH_ID = :V_BATCH_ID;

    SELECT COUNT(*) INTO :V_SHIPMENTS_ROWS
    FROM SUPPLY_CHAIN_DW.RAW.SHIPMENTS
    WHERE LOAD_BATCH_ID = :V_BATCH_ID;

    SELECT COUNT(*) INTO :V_SHIPMENT_LINES_ROWS
    FROM SUPPLY_CHAIN_DW.RAW.SHIPMENT_LINES
    WHERE LOAD_BATCH_ID = :V_BATCH_ID;

    SELECT COUNT(*) INTO :V_SHIPMENT_EVENTS_ROWS
    FROM SUPPLY_CHAIN_DW.RAW.SHIPMENT_EVENTS
    WHERE LOAD_BATCH_ID = :V_BATCH_ID;

    SELECT COUNT(*) INTO :V_TELEMETRY_ROWS
    FROM SUPPLY_CHAIN_DW.RAW.VEHICLE_TELEMETRY
    WHERE LOAD_BATCH_ID = :V_BATCH_ID;


    V_RAW_ROWS :=
          V_ORDERS_ROWS
        + V_ORDER_LINES_ROWS
        + V_INVENTORY_ROWS
        + V_SUPPLIER_PARTS_ROWS
        + V_SUPPLIER_PERF_ROWS
        + V_SHIPMENTS_ROWS
        + V_SHIPMENT_LINES_ROWS
        + V_SHIPMENT_EVENTS_ROWS
        + V_TELEMETRY_ROWS;


    -- =========================================================================
    -- 2. Derive the number of CDC pipelines that should have executed
    -- =========================================================================
    -- ORDERS and ORDER_LINES jointly feed one FACT_ORDER_LINE pipeline.
    -- All other non-empty RAW sources map 1:1 to one Silver pipeline.
    -- =========================================================================

    V_EXPECTED_PIPELINES :=
          IFF(V_ORDERS_ROWS > 0 OR V_ORDER_LINES_ROWS > 0, 1, 0)
        + IFF(V_INVENTORY_ROWS > 0,       1, 0)
        + IFF(V_SUPPLIER_PARTS_ROWS > 0,  1, 0)
        + IFF(V_SUPPLIER_PERF_ROWS > 0,   1, 0)
        + IFF(V_SHIPMENTS_ROWS > 0,       1, 0)
        + IFF(V_SHIPMENT_LINES_ROWS > 0,  1, 0)
        + IFF(V_SHIPMENT_EVENTS_ROWS > 0, 1, 0)
        + IFF(V_TELEMETRY_ROWS > 0,       1, 0);


    -- =========================================================================
    -- 3. Confirm CDC procedure success/failure in the run log
    -- =========================================================================

    SELECT COUNT(DISTINCT PIPELINE_NAME)
      INTO :V_SUCCESSFUL_PIPELINES
    FROM SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
    WHERE STATUS = 'SUCCESS'
      AND POSITION(:V_BATCH_ID IN COALESCE(LOAD_BATCH_IDS, '')) > 0;


    SELECT COUNT(DISTINCT PIPELINE_NAME)
      INTO :V_FAILED_PIPELINES
    FROM SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
    WHERE STATUS = 'FAILED'
      AND POSITION(:V_BATCH_ID IN COALESCE(LOAD_BATCH_IDS, '')) > 0;


    -- =========================================================================
    -- 4. Validate Silver business grains after CDC processing
    -- =========================================================================

    SELECT COUNT(*)
      INTO :V_DUPLICATE_GROUPS
    FROM (
        SELECT 'FACT_ORDER_LINE' AS TARGET_NAME
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE
        GROUP BY ORDER_LINE_ID
        HAVING COUNT(*) > 1

        UNION ALL

        SELECT 'FACT_SHIPMENT'
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT
        GROUP BY SHIPMENT_ID
        HAVING COUNT(*) > 1

        UNION ALL

        SELECT 'FACT_INVENTORY_SNAPSHOT'
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT
        GROUP BY PLANT_ID, PART_ID
        HAVING COUNT(*) > 1

        UNION ALL

        SELECT 'FACT_SUPPLIER_PERFORMANCE'
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE
        GROUP BY SUPPLIER_ID, MEASUREMENT_DATE_KEY
        HAVING COUNT(*) > 1

        UNION ALL

        SELECT 'BRIDGE_SUPPLIER_PART'
        FROM SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART
        GROUP BY SUPPLIER_ID, PART_ID
        HAVING COUNT(*) > 1

        UNION ALL

        SELECT 'FACT_SHIPMENT_LINE'
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE
        GROUP BY SHIPMENT_LINE_ID
        HAVING COUNT(*) > 1

        UNION ALL

        SELECT 'FACT_SHIPMENT_EVENT'
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT
        GROUP BY SHIPMENT_EVENT_ID
        HAVING COUNT(*) > 1

        UNION ALL

        SELECT 'FACT_VEHICLE_TELEMETRY'
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY
        GROUP BY TELEMETRY_ID
        HAVING COUNT(*) > 1
    );


    -- =========================================================================
    -- 5. Overall result
    -- =========================================================================

    V_PASS :=
           V_RAW_ROWS > 0
       AND V_FAILED_PIPELINES = 0
       AND V_SUCCESSFUL_PIPELINES >= V_EXPECTED_PIPELINES
       AND V_DUPLICATE_GROUPS = 0;


    RETURN OBJECT_CONSTRUCT(
        'status',
            IFF(V_PASS, 'PASS', 'NOT_READY_OR_FAIL'),

        'load_batch_id',
            V_BATCH_ID,

        'raw_rows',
            V_RAW_ROWS,

        'raw_table_rows',
            OBJECT_CONSTRUCT(
                'ORDERS', V_ORDERS_ROWS,
                'ORDER_LINES', V_ORDER_LINES_ROWS,
                'INVENTORY', V_INVENTORY_ROWS,
                'SUPPLIER_PARTS', V_SUPPLIER_PARTS_ROWS,
                'SUPPLIER_PERFORMANCE', V_SUPPLIER_PERF_ROWS,
                'SHIPMENTS', V_SHIPMENTS_ROWS,
                'SHIPMENT_LINES', V_SHIPMENT_LINES_ROWS,
                'SHIPMENT_EVENTS', V_SHIPMENT_EVENTS_ROWS,
                'VEHICLE_TELEMETRY', V_TELEMETRY_ROWS
            ),

        'expected_pipelines',
            V_EXPECTED_PIPELINES,

        'successful_pipelines',
            V_SUCCESSFUL_PIPELINES,

        'failed_pipelines',
            V_FAILED_PIPELINES,

        'silver_duplicate_groups',
            V_DUPLICATE_GROUPS,

        'interpretation',
            IFF(
                V_PASS,
                'Controlled batch passed RAW -> task/procedure -> Silver checks.',
                'If tasks were just triggered, wait for them to finish and run this validator again. Otherwise inspect CDC_STREAM_RUN_LOG.'
            )
    );

END;
$$;


-- =============================================================================
-- Manual controlled-test workflow — intentionally NOT executed by migration
-- =============================================================================
--
-- 1. Confirm V3.13.0 tasks are resumed.
--
-- 2. Load ONE known incremental batch:
--
--    CALL SUPPLY_CHAIN_DW.CONTROL.SP_LOAD_INCREMENTAL_RAW_BATCH(
--        '20260924_0630'
--    );
--
-- 3. Inspect task execution if needed:
--
--    SELECT *
--    FROM TABLE(
--        INFORMATION_SCHEMA.TASK_HISTORY(
--            SCHEDULED_TIME_RANGE_START =>
--                DATEADD('HOUR', -1, CURRENT_TIMESTAMP())
--        )
--    )
--    WHERE NAME LIKE 'TASK_CDC_%'
--    ORDER BY SCHEDULED_TIME DESC;
--
-- 4. Validate the batch after tasks complete:
--
--    CALL SUPPLY_CHAIN_DW.CONTROL.SP_VALIDATE_CDC_BATCH(
--        '20260924_0630'
--    );
--
-- Expected final status: PASS
--
-- =============================================================================
