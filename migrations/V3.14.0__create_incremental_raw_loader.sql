-- =============================================================================
-- V3.14.0 — Create Incremental RAW Batch Loader
-- =============================================================================
-- Purpose:
--   Load one incremental batch suffix from S3 into all 9 incremental RAW tables.
--
-- Example:
--   CALL SUPPLY_CHAIN_DW.CONTROL.SP_LOAD_INCREMENTAL_RAW_BATCH('20260924_0630');
--   CALL SUPPLY_CHAIN_DW.CONTROL.SP_LOAD_INCREMENTAL_RAW_BATCH('20260924_0000');
--
-- Behaviour:
--   * The same batch suffix is checked across all 9 incremental folders.
--   * If a particular file does not exist for that slot, COPY loads 0 rows.
--     This supports sparse SHIPMENT_LINES and IoT-only time slots.
--   * Snowflake COPY load history prevents an already-loaded file from being
--     loaded again unless FORCE = TRUE. FORCE is intentionally NOT used.
--   * Successful COPY operations append rows to RAW; the V3.8.0 streams then
--     expose those rows to the V3.11.0 triggered CDC tasks.
--
-- File naming:
--   <table>_YYYYMMDD_HHMM.csv
--
-- Metadata:
--   LOAD_BATCH_ID      = INCR_YYYYMMDD_HHMM
--   SOURCE_BATCH_TYPE  = INCREMENTAL
--   SOURCE_BATCH_TS    = parsed from YYYYMMDD_HHMM
--   SOURCE_FILE_NAME   = METADATA$FILENAME
--   LOADED_AT          = CURRENT_TIMESTAMP()
--
-- Preconditions:
--   SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE exists
--   SUPPLY_CHAIN_DW.RAW.CSV_FORMAT exists
--   RAW tables already exist
-- =============================================================================

USE DATABASE SUPPLY_CHAIN_DW;
USE SCHEMA CONTROL;


CREATE OR REPLACE PROCEDURE
SUPPLY_CHAIN_DW.CONTROL.SP_LOAD_INCREMENTAL_RAW_BATCH(P_BATCH_SUFFIX VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_BATCH_ID VARCHAR;
    V_BATCH_TS TIMESTAMP_NTZ;
    V_TS_EXPR  VARCHAR;
    V_SQL      VARCHAR;
BEGIN

    -- -------------------------------------------------------------------------
    -- Validate caller input before using it in dynamic SQL.
    -- -------------------------------------------------------------------------
    IF (
        P_BATCH_SUFFIX IS NULL
        OR NOT REGEXP_LIKE(P_BATCH_SUFFIX, '^[0-9]{8}_[0-9]{4}$')
    ) THEN
        RETURN
            'INVALID_BATCH_SUFFIX | expected YYYYMMDD_HHMM, e.g. 20260924_0630';
    END IF;

    V_BATCH_ID := 'INCR_' || P_BATCH_SUFFIX;
    V_BATCH_TS := TO_TIMESTAMP_NTZ(P_BATCH_SUFFIX, 'YYYYMMDD_HH24MI');

    IF (V_BATCH_TS IS NULL) THEN
        RETURN
            'INVALID_BATCH_SUFFIX | timestamp cannot be parsed: ' ||
            P_BATCH_SUFFIX;
    END IF;

    -- Used inside generated COPY statements.
    V_TS_EXPR :=
        'TO_TIMESTAMP_NTZ(''' || P_BATCH_SUFFIX ||
        ''',''YYYYMMDD_HH24MI'')';


    -- =========================================================================
    -- 1. ORDERS
    -- 8 business columns + 2 generator metadata columns
    -- =========================================================================

    V_SQL :=
        'COPY INTO SUPPLY_CHAIN_DW.RAW.ORDERS ' ||
        'FROM ( ' ||
        'SELECT ' ||
        '$1,$2,$3,$4,$5,$6,$7,$8,$9,$10, ' ||
        '''' || V_BATCH_ID || ''', ' ||
        'METADATA$FILENAME, ' ||
        '''INCREMENTAL'', ' ||
        V_TS_EXPR || ', ' ||
        'CURRENT_TIMESTAMP()::TIMESTAMP_NTZ ' ||
        'FROM @SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE/erp/orders/ ' ||
        ') ' ||
        'PATTERN = ''.*orders_' || P_BATCH_SUFFIX || '[.]csv'' ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''SUPPLY_CHAIN_DW.RAW.CSV_FORMAT'') ' ||
        'ON_ERROR = ''ABORT_STATEMENT''';

    EXECUTE IMMEDIATE :V_SQL;


    -- =========================================================================
    -- 2. ORDER_LINES
    -- 9 business columns + 2 generator metadata columns
    -- =========================================================================

    V_SQL :=
        'COPY INTO SUPPLY_CHAIN_DW.RAW.ORDER_LINES ' ||
        'FROM ( ' ||
        'SELECT ' ||
        '$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, ' ||
        '''' || V_BATCH_ID || ''', ' ||
        'METADATA$FILENAME, ' ||
        '''INCREMENTAL'', ' ||
        V_TS_EXPR || ', ' ||
        'CURRENT_TIMESTAMP()::TIMESTAMP_NTZ ' ||
        'FROM @SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE/erp/order_lines/ ' ||
        ') ' ||
        'PATTERN = ''.*order_lines_' || P_BATCH_SUFFIX || '[.]csv'' ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''SUPPLY_CHAIN_DW.RAW.CSV_FORMAT'') ' ||
        'ON_ERROR = ''ABORT_STATEMENT''';

    EXECUTE IMMEDIATE :V_SQL;


    -- =========================================================================
    -- 3. INVENTORY
    -- 9 business columns + 2 generator metadata columns
    -- =========================================================================

    V_SQL :=
        'COPY INTO SUPPLY_CHAIN_DW.RAW.INVENTORY ' ||
        'FROM ( ' ||
        'SELECT ' ||
        '$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, ' ||
        '''' || V_BATCH_ID || ''', ' ||
        'METADATA$FILENAME, ' ||
        '''INCREMENTAL'', ' ||
        V_TS_EXPR || ', ' ||
        'CURRENT_TIMESTAMP()::TIMESTAMP_NTZ ' ||
        'FROM @SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE/erp/inventory/ ' ||
        ') ' ||
        'PATTERN = ''.*inventory_' || P_BATCH_SUFFIX || '[.]csv'' ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''SUPPLY_CHAIN_DW.RAW.CSV_FORMAT'') ' ||
        'ON_ERROR = ''ABORT_STATEMENT''';

    EXECUTE IMMEDIATE :V_SQL;


    -- =========================================================================
    -- 4. SUPPLIER_PARTS
    -- 8 business columns + 2 generator metadata columns
    -- =========================================================================

    V_SQL :=
        'COPY INTO SUPPLY_CHAIN_DW.RAW.SUPPLIER_PARTS ' ||
        'FROM ( ' ||
        'SELECT ' ||
        '$1,$2,$3,$4,$5,$6,$7,$8,$9,$10, ' ||
        '''' || V_BATCH_ID || ''', ' ||
        'METADATA$FILENAME, ' ||
        '''INCREMENTAL'', ' ||
        V_TS_EXPR || ', ' ||
        'CURRENT_TIMESTAMP()::TIMESTAMP_NTZ ' ||
        'FROM @SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE/supplier/supplier_parts/ ' ||
        ') ' ||
        'PATTERN = ''.*supplier_parts_' || P_BATCH_SUFFIX || '[.]csv'' ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''SUPPLY_CHAIN_DW.RAW.CSV_FORMAT'') ' ||
        'ON_ERROR = ''ABORT_STATEMENT''';

    EXECUTE IMMEDIATE :V_SQL;


    -- =========================================================================
    -- 5. SUPPLIER_PERFORMANCE
    -- 9 business columns + 2 generator metadata columns
    -- =========================================================================

    V_SQL :=
        'COPY INTO SUPPLY_CHAIN_DW.RAW.SUPPLIER_PERFORMANCE ' ||
        'FROM ( ' ||
        'SELECT ' ||
        '$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, ' ||
        '''' || V_BATCH_ID || ''', ' ||
        'METADATA$FILENAME, ' ||
        '''INCREMENTAL'', ' ||
        V_TS_EXPR || ', ' ||
        'CURRENT_TIMESTAMP()::TIMESTAMP_NTZ ' ||
        'FROM @SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE/supplier/supplier_performance/ ' ||
        ') ' ||
        'PATTERN = ''.*supplier_performance_' || P_BATCH_SUFFIX || '[.]csv'' ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''SUPPLY_CHAIN_DW.RAW.CSV_FORMAT'') ' ||
        'ON_ERROR = ''ABORT_STATEMENT''';

    EXECUTE IMMEDIATE :V_SQL;


    -- =========================================================================
    -- 6. SHIPMENTS
    -- 11 business columns + 2 generator metadata columns
    -- =========================================================================

    V_SQL :=
        'COPY INTO SUPPLY_CHAIN_DW.RAW.SHIPMENTS ' ||
        'FROM ( ' ||
        'SELECT ' ||
        '$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13, ' ||
        '''' || V_BATCH_ID || ''', ' ||
        'METADATA$FILENAME, ' ||
        '''INCREMENTAL'', ' ||
        V_TS_EXPR || ', ' ||
        'CURRENT_TIMESTAMP()::TIMESTAMP_NTZ ' ||
        'FROM @SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE/logistics/shipments/ ' ||
        ') ' ||
        'PATTERN = ''.*shipments_' || P_BATCH_SUFFIX || '[.]csv'' ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''SUPPLY_CHAIN_DW.RAW.CSV_FORMAT'') ' ||
        'ON_ERROR = ''ABORT_STATEMENT''';

    EXECUTE IMMEDIATE :V_SQL;


    -- =========================================================================
    -- 7. SHIPMENT_LINES
    -- 6 business columns + 2 generator metadata columns
    -- Sparse incremental dataset: many slots legitimately have no file.
    -- =========================================================================

    V_SQL :=
        'COPY INTO SUPPLY_CHAIN_DW.RAW.SHIPMENT_LINES ' ||
        'FROM ( ' ||
        'SELECT ' ||
        '$1,$2,$3,$4,$5,$6,$7,$8, ' ||
        '''' || V_BATCH_ID || ''', ' ||
        'METADATA$FILENAME, ' ||
        '''INCREMENTAL'', ' ||
        V_TS_EXPR || ', ' ||
        'CURRENT_TIMESTAMP()::TIMESTAMP_NTZ ' ||
        'FROM @SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE/logistics/shipment_lines/ ' ||
        ') ' ||
        'PATTERN = ''.*shipment_lines_' || P_BATCH_SUFFIX || '[.]csv'' ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''SUPPLY_CHAIN_DW.RAW.CSV_FORMAT'') ' ||
        'ON_ERROR = ''ABORT_STATEMENT''';

    EXECUTE IMMEDIATE :V_SQL;


    -- =========================================================================
    -- 8. SHIPMENT_EVENTS
    -- 7 business columns + 2 generator metadata columns
    -- =========================================================================

    V_SQL :=
        'COPY INTO SUPPLY_CHAIN_DW.RAW.SHIPMENT_EVENTS ' ||
        'FROM ( ' ||
        'SELECT ' ||
        '$1,$2,$3,$4,$5,$6,$7,$8,$9, ' ||
        '''' || V_BATCH_ID || ''', ' ||
        'METADATA$FILENAME, ' ||
        '''INCREMENTAL'', ' ||
        V_TS_EXPR || ', ' ||
        'CURRENT_TIMESTAMP()::TIMESTAMP_NTZ ' ||
        'FROM @SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE/logistics/shipment_events/ ' ||
        ') ' ||
        'PATTERN = ''.*shipment_events_' || P_BATCH_SUFFIX || '[.]csv'' ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''SUPPLY_CHAIN_DW.RAW.CSV_FORMAT'') ' ||
        'ON_ERROR = ''ABORT_STATEMENT''';

    EXECUTE IMMEDIATE :V_SQL;


    -- =========================================================================
    -- 9. VEHICLE_TELEMETRY
    -- 9 business columns + 2 generator metadata columns
    -- Hourly dataset; the procedure safely loads 0 rows when no file matches.
    -- =========================================================================

    V_SQL :=
        'COPY INTO SUPPLY_CHAIN_DW.RAW.VEHICLE_TELEMETRY ' ||
        'FROM ( ' ||
        'SELECT ' ||
        '$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, ' ||
        '''' || V_BATCH_ID || ''', ' ||
        'METADATA$FILENAME, ' ||
        '''INCREMENTAL'', ' ||
        V_TS_EXPR || ', ' ||
        'CURRENT_TIMESTAMP()::TIMESTAMP_NTZ ' ||
        'FROM @SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE/iot/vehicle_telemetry/ ' ||
        ') ' ||
        'PATTERN = ''.*vehicle_telemetry_' || P_BATCH_SUFFIX || '[.]csv'' ' ||
        'FILE_FORMAT = (FORMAT_NAME = ''SUPPLY_CHAIN_DW.RAW.CSV_FORMAT'') ' ||
        'ON_ERROR = ''ABORT_STATEMENT''';

    EXECUTE IMMEDIATE :V_SQL;


    RETURN
        'SUCCESS | LOAD_BATCH_ID=' || V_BATCH_ID ||
        ' | SOURCE_BATCH_TS=' || TO_VARCHAR(V_BATCH_TS);

EXCEPTION
    WHEN OTHER THEN
        RETURN
            'FAILED | LOAD_BATCH_ID=' ||
            COALESCE(V_BATCH_ID, 'UNKNOWN') ||
            ' | ERROR=' || SQLERRM;
END;
$$;


-- =============================================================================
-- Manual usage example — intentionally NOT executed by this migration
-- =============================================================================
-- CALL SUPPLY_CHAIN_DW.CONTROL.SP_LOAD_INCREMENTAL_RAW_BATCH(
--     '20260924_0630'
-- );
--
-- After the call:
--   1. RAW rows with LOAD_BATCH_ID='INCR_20260924_0630' should exist
--      for the files present in that slot.
--   2. Resumed V3.11.0 triggered tasks should process the corresponding streams.
--   3. Use the V3.15.0 batch validator after task processing completes.
-- =============================================================================
