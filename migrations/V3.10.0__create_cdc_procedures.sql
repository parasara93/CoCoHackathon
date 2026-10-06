-- =============================================================================
-- V3.10.0 — Create RAW -> SILVER CDC Procedures
-- =============================================================================
-- Design:
--   * RAW tables are append-only.
--   * Streams identify newly arrived RAW rows.
--   * Updatable Silver targets:
--       - identify affected business keys from the Stream,
--       - recompute the latest authoritative version from full RAW,
--       - MERGE using business timestamp guards.
--   * Append-only Silver targets:
--       - INSERT directly from the Stream,
--       - deduplicate by target grain,
--       - suppress keys already present in Silver.
--   * No CTAS / CREATE TEMP TABLE occurs inside a transaction.
--     Stream-consuming DML and Silver writes therefore commit/rollback atomically.
--
-- Requires:
--   V3.8.0 RAW CDC streams
--   V3.9.0 CONTROL.CDC_STREAM_RUN_LOG
-- =============================================================================

USE DATABASE SUPPLY_CHAIN_DW;
USE SCHEMA CONTROL;


-- =============================================================================
-- 1. FACT_INVENTORY_SNAPSHOT
-- RAW source: INVENTORY
-- Grain: PLANT_ID + PART_ID
-- Strategy: MERGE
-- =============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_INVENTORY_SNAPSHOT()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID     VARCHAR DEFAULT UUID_STRING();
    V_CAPTURED   NUMBER  DEFAULT 0;
    V_INSERTED   NUMBER  DEFAULT 0;
    V_UPDATED    NUMBER  DEFAULT 0;
    V_SKIPPED    NUMBER  DEFAULT 0;
    V_BATCH_IDS  VARCHAR DEFAULT NULL;
BEGIN

    SELECT
        COUNT(*),
        LISTAGG(DISTINCT LOAD_BATCH_ID, ',')
            WITHIN GROUP (ORDER BY LOAD_BATCH_ID)
    INTO
        :V_CAPTURED,
        :V_BATCH_IDS
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_INVENTORY;

    IF (V_CAPTURED = 0) THEN
        RETURN 'NO_DATA';
    END IF;

    BEGIN TRANSACTION;

    INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
        RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
        STARTED_AT, ROWS_CAPTURED, ROWS_INSERTED,
        ROWS_UPDATED, ROWS_SKIPPED, STATUS, LOAD_BATCH_IDS
    )
    VALUES (
        :V_RUN_ID,
        'CDC_FACT_INVENTORY_SNAPSHOT',
        'RAW.INVENTORY',
        'SILVER.FACT_INVENTORY_SNAPSHOT',
        CURRENT_TIMESTAMP(),
        :V_CAPTURED,
        0, 0, 0,
        'RUNNING',
        :V_BATCH_IDS
    );

    MERGE INTO SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT T
    USING (
        WITH AFFECTED_KEYS AS (
            SELECT DISTINCT PLANT_ID, PART_ID
            FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_INVENTORY
        ),
        LATEST_RAW AS (
            SELECT
                R.PLANT_ID,
                R.PART_ID,
                R.ON_HAND_QTY,
                R.RESERVED_QTY,
                R.AVAILABLE_QTY,
                R.SAFETY_STOCK,
                R.REORDER_POINT,
                R.INVENTORY_STATUS,
                R.LAST_UPDATED_AT,
                R.LAST_UPDATED_AT::DATE AS SNAPSHOT_DATE_KEY,
                (R.AVAILABLE_QTY <= R.REORDER_POINT) AS NEEDS_REORDER,
                (R.AVAILABLE_QTY <= R.SAFETY_STOCK) AS BELOW_SAFETY_STOCK
            FROM SUPPLY_CHAIN_DW.RAW.INVENTORY R
            INNER JOIN AFFECTED_KEYS K
                ON R.PLANT_ID = K.PLANT_ID
               AND R.PART_ID  = K.PART_ID
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY R.PLANT_ID, R.PART_ID
                ORDER BY
                    R.LAST_UPDATED_AT DESC,
                    R.LOADED_AT DESC,
                    R.SOURCE_BATCH_TS DESC
            ) = 1
        )
        SELECT * FROM LATEST_RAW
    ) S
       ON T.PLANT_ID = S.PLANT_ID
      AND T.PART_ID  = S.PART_ID

    WHEN MATCHED
         AND S.LAST_UPDATED_AT > T.LAST_UPDATED_AT
    THEN UPDATE SET
        T.ON_HAND_QTY        = S.ON_HAND_QTY,
        T.RESERVED_QTY       = S.RESERVED_QTY,
        T.AVAILABLE_QTY      = S.AVAILABLE_QTY,
        T.SAFETY_STOCK       = S.SAFETY_STOCK,
        T.REORDER_POINT      = S.REORDER_POINT,
        T.INVENTORY_STATUS   = S.INVENTORY_STATUS,
        T.SNAPSHOT_DATE_KEY  = S.SNAPSHOT_DATE_KEY,
        T.NEEDS_REORDER      = S.NEEDS_REORDER,
        T.BELOW_SAFETY_STOCK = S.BELOW_SAFETY_STOCK,
        T.LAST_UPDATED_AT    = S.LAST_UPDATED_AT

    WHEN NOT MATCHED
    THEN INSERT (
        PLANT_ID,
        PART_ID,
        ON_HAND_QTY,
        RESERVED_QTY,
        AVAILABLE_QTY,
        SAFETY_STOCK,
        REORDER_POINT,
        INVENTORY_STATUS,
        SNAPSHOT_DATE_KEY,
        NEEDS_REORDER,
        BELOW_SAFETY_STOCK,
        LAST_UPDATED_AT
    )
    VALUES (
        S.PLANT_ID,
        S.PART_ID,
        S.ON_HAND_QTY,
        S.RESERVED_QTY,
        S.AVAILABLE_QTY,
        S.SAFETY_STOCK,
        S.REORDER_POINT,
        S.INVENTORY_STATUS,
        S.SNAPSHOT_DATE_KEY,
        S.NEEDS_REORDER,
        S.BELOW_SAFETY_STOCK,
        S.LAST_UPDATED_AT
    );

    SELECT
        COALESCE("number of rows inserted", 0),
        COALESCE("number of rows updated", 0)
    INTO
        :V_INSERTED,
        :V_UPDATED
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    V_SKIPPED := GREATEST(V_CAPTURED - V_INSERTED - V_UPDATED, 0);

    UPDATE SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
       SET ROWS_INSERTED = :V_INSERTED,
           ROWS_UPDATED  = :V_UPDATED,
           ROWS_SKIPPED  = :V_SKIPPED,
           STATUS        = 'SUCCESS',
           COMPLETED_AT  = CURRENT_TIMESTAMP()
     WHERE RUN_ID = :V_RUN_ID;

    COMMIT;

    RETURN
        'SUCCESS | RUN_ID=' || V_RUN_ID ||
        ' | CAPTURED=' || V_CAPTURED ||
        ' | INSERTED=' || V_INSERTED ||
        ' | UPDATED=' || V_UPDATED ||
        ' | SKIPPED=' || V_SKIPPED;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;

        INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
            RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
            STARTED_AT, COMPLETED_AT, ROWS_CAPTURED,
            ROWS_INSERTED, ROWS_UPDATED, ROWS_SKIPPED,
            STATUS, ERROR_MESSAGE, LOAD_BATCH_IDS
        )
        VALUES (
            :V_RUN_ID,
            'CDC_FACT_INVENTORY_SNAPSHOT',
            'RAW.INVENTORY',
            'SILVER.FACT_INVENTORY_SNAPSHOT',
            CURRENT_TIMESTAMP(),
            CURRENT_TIMESTAMP(),
            :V_CAPTURED,
            0, 0, 0,
            'FAILED',
            SQLERRM,
            :V_BATCH_IDS
        );

        RAISE;
END;
$$;


-- =============================================================================
-- 2. BRIDGE_SUPPLIER_PART
-- RAW source: SUPPLIER_PARTS
-- Grain: SUPPLIER_ID + PART_ID
-- Strategy: MERGE
-- =============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_DW.CONTROL.SP_CDC_BRIDGE_SUPPLIER_PART()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID     VARCHAR DEFAULT UUID_STRING();
    V_CAPTURED   NUMBER  DEFAULT 0;
    V_INSERTED   NUMBER  DEFAULT 0;
    V_UPDATED    NUMBER  DEFAULT 0;
    V_SKIPPED    NUMBER  DEFAULT 0;
    V_BATCH_IDS  VARCHAR DEFAULT NULL;
BEGIN

    SELECT
        COUNT(*),
        LISTAGG(DISTINCT LOAD_BATCH_ID, ',')
            WITHIN GROUP (ORDER BY LOAD_BATCH_ID)
    INTO
        :V_CAPTURED,
        :V_BATCH_IDS
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SUPPLIER_PARTS;

    IF (V_CAPTURED = 0) THEN
        RETURN 'NO_DATA';
    END IF;

    BEGIN TRANSACTION;

    INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
        RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
        STARTED_AT, ROWS_CAPTURED, ROWS_INSERTED,
        ROWS_UPDATED, ROWS_SKIPPED, STATUS, LOAD_BATCH_IDS
    )
    VALUES (
        :V_RUN_ID,
        'CDC_BRIDGE_SUPPLIER_PART',
        'RAW.SUPPLIER_PARTS',
        'SILVER.BRIDGE_SUPPLIER_PART',
        CURRENT_TIMESTAMP(),
        :V_CAPTURED,
        0, 0, 0,
        'RUNNING',
        :V_BATCH_IDS
    );

    MERGE INTO SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART T
    USING (
        WITH AFFECTED_KEYS AS (
            SELECT DISTINCT SUPPLIER_ID, PART_ID
            FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SUPPLIER_PARTS
        ),
        LATEST_RAW AS (
            SELECT
                R.SUPPLIER_ID,
                R.PART_ID,
                R.SUPPLIER_UNIT_COST,
                R.BASE_LEAD_TIME_DAYS,
                R.MINIMUM_ORDER_QTY,
                R.PREFERRED_SUPPLIER_FLAG,
                R.ACTIVE_FLAG,
                R.LAST_UPDATED_AT
            FROM SUPPLY_CHAIN_DW.RAW.SUPPLIER_PARTS R
            INNER JOIN AFFECTED_KEYS K
                ON R.SUPPLIER_ID = K.SUPPLIER_ID
               AND R.PART_ID     = K.PART_ID
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY R.SUPPLIER_ID, R.PART_ID
                ORDER BY
                    R.LAST_UPDATED_AT DESC,
                    R.LOADED_AT DESC,
                    R.SOURCE_BATCH_TS DESC
            ) = 1
        )
        SELECT * FROM LATEST_RAW
    ) S
       ON T.SUPPLIER_ID = S.SUPPLIER_ID
      AND T.PART_ID     = S.PART_ID

    WHEN MATCHED
         AND S.LAST_UPDATED_AT > T.LAST_UPDATED_AT
    THEN UPDATE SET
        T.SUPPLIER_UNIT_COST      = S.SUPPLIER_UNIT_COST,
        T.BASE_LEAD_TIME_DAYS     = S.BASE_LEAD_TIME_DAYS,
        T.MINIMUM_ORDER_QTY       = S.MINIMUM_ORDER_QTY,
        T.PREFERRED_SUPPLIER_FLAG = S.PREFERRED_SUPPLIER_FLAG,
        T.ACTIVE_FLAG             = S.ACTIVE_FLAG,
        T.LAST_UPDATED_AT         = S.LAST_UPDATED_AT

    WHEN NOT MATCHED
    THEN INSERT (
        SUPPLIER_ID,
        PART_ID,
        SUPPLIER_UNIT_COST,
        BASE_LEAD_TIME_DAYS,
        MINIMUM_ORDER_QTY,
        PREFERRED_SUPPLIER_FLAG,
        ACTIVE_FLAG,
        LAST_UPDATED_AT
    )
    VALUES (
        S.SUPPLIER_ID,
        S.PART_ID,
        S.SUPPLIER_UNIT_COST,
        S.BASE_LEAD_TIME_DAYS,
        S.MINIMUM_ORDER_QTY,
        S.PREFERRED_SUPPLIER_FLAG,
        S.ACTIVE_FLAG,
        S.LAST_UPDATED_AT
    );

    SELECT
        COALESCE("number of rows inserted", 0),
        COALESCE("number of rows updated", 0)
    INTO
        :V_INSERTED,
        :V_UPDATED
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    V_SKIPPED := GREATEST(V_CAPTURED - V_INSERTED - V_UPDATED, 0);

    UPDATE SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
       SET ROWS_INSERTED = :V_INSERTED,
           ROWS_UPDATED  = :V_UPDATED,
           ROWS_SKIPPED  = :V_SKIPPED,
           STATUS        = 'SUCCESS',
           COMPLETED_AT  = CURRENT_TIMESTAMP()
     WHERE RUN_ID = :V_RUN_ID;

    COMMIT;

    RETURN
        'SUCCESS | RUN_ID=' || V_RUN_ID ||
        ' | CAPTURED=' || V_CAPTURED ||
        ' | INSERTED=' || V_INSERTED ||
        ' | UPDATED=' || V_UPDATED ||
        ' | SKIPPED=' || V_SKIPPED;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;

        INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
            RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
            STARTED_AT, COMPLETED_AT, ROWS_CAPTURED,
            ROWS_INSERTED, ROWS_UPDATED, ROWS_SKIPPED,
            STATUS, ERROR_MESSAGE, LOAD_BATCH_IDS
        )
        VALUES (
            :V_RUN_ID,
            'CDC_BRIDGE_SUPPLIER_PART',
            'RAW.SUPPLIER_PARTS',
            'SILVER.BRIDGE_SUPPLIER_PART',
            CURRENT_TIMESTAMP(),
            CURRENT_TIMESTAMP(),
            :V_CAPTURED,
            0, 0, 0,
            'FAILED',
            SQLERRM,
            :V_BATCH_IDS
        );

        RAISE;
END;
$$;


-- =============================================================================
-- 3. FACT_SUPPLIER_PERFORMANCE
-- RAW source: SUPPLIER_PERFORMANCE
-- Grain: SUPPLIER_ID + MEASUREMENT_DATE_KEY
-- Strategy: MERGE
-- =============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SUPPLIER_PERFORMANCE()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID     VARCHAR DEFAULT UUID_STRING();
    V_CAPTURED   NUMBER  DEFAULT 0;
    V_INSERTED   NUMBER  DEFAULT 0;
    V_UPDATED    NUMBER  DEFAULT 0;
    V_SKIPPED    NUMBER  DEFAULT 0;
    V_BATCH_IDS  VARCHAR DEFAULT NULL;
BEGIN

    SELECT
        COUNT(*),
        LISTAGG(DISTINCT LOAD_BATCH_ID, ',')
            WITHIN GROUP (ORDER BY LOAD_BATCH_ID)
    INTO
        :V_CAPTURED,
        :V_BATCH_IDS
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SUPPLIER_PERFORMANCE;

    IF (V_CAPTURED = 0) THEN
        RETURN 'NO_DATA';
    END IF;

    BEGIN TRANSACTION;

    INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
        RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
        STARTED_AT, ROWS_CAPTURED, ROWS_INSERTED,
        ROWS_UPDATED, ROWS_SKIPPED, STATUS, LOAD_BATCH_IDS
    )
    VALUES (
        :V_RUN_ID,
        'CDC_FACT_SUPPLIER_PERFORMANCE',
        'RAW.SUPPLIER_PERFORMANCE',
        'SILVER.FACT_SUPPLIER_PERFORMANCE',
        CURRENT_TIMESTAMP(),
        :V_CAPTURED,
        0, 0, 0,
        'RUNNING',
        :V_BATCH_IDS
    );

    MERGE INTO SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE T
    USING (
        WITH AFFECTED_KEYS AS (
            SELECT DISTINCT SUPPLIER_ID, MEASUREMENT_DATE
            FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SUPPLIER_PERFORMANCE
        ),
        LATEST_RAW AS (
            SELECT
                R.SUPPLIER_PERFORMANCE_ID,
                R.SUPPLIER_ID,
                R.MEASUREMENT_DATE AS MEASUREMENT_DATE_KEY,
                R.AVG_LEAD_TIME_DAYS,
                R.ON_TIME_DELIVERY_PCT,
                R.QUALITY_SCORE,
                R.FILL_RATE_PCT,
                R.RISK_SCORE,
                R.LAST_UPDATED_AT
            FROM SUPPLY_CHAIN_DW.RAW.SUPPLIER_PERFORMANCE R
            INNER JOIN AFFECTED_KEYS K
                ON R.SUPPLIER_ID      = K.SUPPLIER_ID
               AND R.MEASUREMENT_DATE = K.MEASUREMENT_DATE
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY R.SUPPLIER_ID, R.MEASUREMENT_DATE
                ORDER BY
                    R.LAST_UPDATED_AT DESC,
                    R.LOADED_AT DESC,
                    R.SOURCE_BATCH_TS DESC
            ) = 1
        )
        SELECT * FROM LATEST_RAW
    ) S
       ON T.SUPPLIER_ID          = S.SUPPLIER_ID
      AND T.MEASUREMENT_DATE_KEY = S.MEASUREMENT_DATE_KEY

    WHEN MATCHED
         AND S.LAST_UPDATED_AT > T.LAST_UPDATED_AT
    THEN UPDATE SET
        T.SUPPLIER_PERFORMANCE_ID = S.SUPPLIER_PERFORMANCE_ID,
        T.AVG_LEAD_TIME_DAYS       = S.AVG_LEAD_TIME_DAYS,
        T.ON_TIME_DELIVERY_PCT     = S.ON_TIME_DELIVERY_PCT,
        T.QUALITY_SCORE            = S.QUALITY_SCORE,
        T.FILL_RATE_PCT            = S.FILL_RATE_PCT,
        T.RISK_SCORE               = S.RISK_SCORE,
        T.LAST_UPDATED_AT          = S.LAST_UPDATED_AT

    WHEN NOT MATCHED
    THEN INSERT (
        SUPPLIER_PERFORMANCE_ID,
        SUPPLIER_ID,
        MEASUREMENT_DATE_KEY,
        AVG_LEAD_TIME_DAYS,
        ON_TIME_DELIVERY_PCT,
        QUALITY_SCORE,
        FILL_RATE_PCT,
        RISK_SCORE,
        LAST_UPDATED_AT
    )
    VALUES (
        S.SUPPLIER_PERFORMANCE_ID,
        S.SUPPLIER_ID,
        S.MEASUREMENT_DATE_KEY,
        S.AVG_LEAD_TIME_DAYS,
        S.ON_TIME_DELIVERY_PCT,
        S.QUALITY_SCORE,
        S.FILL_RATE_PCT,
        S.RISK_SCORE,
        S.LAST_UPDATED_AT
    );

    SELECT
        COALESCE("number of rows inserted", 0),
        COALESCE("number of rows updated", 0)
    INTO
        :V_INSERTED,
        :V_UPDATED
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    V_SKIPPED := GREATEST(V_CAPTURED - V_INSERTED - V_UPDATED, 0);

    UPDATE SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
       SET ROWS_INSERTED = :V_INSERTED,
           ROWS_UPDATED  = :V_UPDATED,
           ROWS_SKIPPED  = :V_SKIPPED,
           STATUS        = 'SUCCESS',
           COMPLETED_AT  = CURRENT_TIMESTAMP()
     WHERE RUN_ID = :V_RUN_ID;

    COMMIT;

    RETURN
        'SUCCESS | RUN_ID=' || V_RUN_ID ||
        ' | CAPTURED=' || V_CAPTURED ||
        ' | INSERTED=' || V_INSERTED ||
        ' | UPDATED=' || V_UPDATED ||
        ' | SKIPPED=' || V_SKIPPED;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;

        INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
            RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
            STARTED_AT, COMPLETED_AT, ROWS_CAPTURED,
            ROWS_INSERTED, ROWS_UPDATED, ROWS_SKIPPED,
            STATUS, ERROR_MESSAGE, LOAD_BATCH_IDS
        )
        VALUES (
            :V_RUN_ID,
            'CDC_FACT_SUPPLIER_PERFORMANCE',
            'RAW.SUPPLIER_PERFORMANCE',
            'SILVER.FACT_SUPPLIER_PERFORMANCE',
            CURRENT_TIMESTAMP(),
            CURRENT_TIMESTAMP(),
            :V_CAPTURED,
            0, 0, 0,
            'FAILED',
            SQLERRM,
            :V_BATCH_IDS
        );

        RAISE;
END;
$$;


-- =============================================================================
-- 4. FACT_SHIPMENT
-- RAW source: SHIPMENTS
-- Grain: SHIPMENT_ID
-- Strategy: MERGE
-- =============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SHIPMENT()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID     VARCHAR DEFAULT UUID_STRING();
    V_CAPTURED   NUMBER  DEFAULT 0;
    V_INSERTED   NUMBER  DEFAULT 0;
    V_UPDATED    NUMBER  DEFAULT 0;
    V_SKIPPED    NUMBER  DEFAULT 0;
    V_BATCH_IDS  VARCHAR DEFAULT NULL;
BEGIN

    SELECT
        COUNT(*),
        LISTAGG(DISTINCT LOAD_BATCH_ID, ',')
            WITHIN GROUP (ORDER BY LOAD_BATCH_ID)
    INTO
        :V_CAPTURED,
        :V_BATCH_IDS
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENTS;

    IF (V_CAPTURED = 0) THEN
        RETURN 'NO_DATA';
    END IF;

    BEGIN TRANSACTION;

    INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
        RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
        STARTED_AT, ROWS_CAPTURED, ROWS_INSERTED,
        ROWS_UPDATED, ROWS_SKIPPED, STATUS, LOAD_BATCH_IDS
    )
    VALUES (
        :V_RUN_ID,
        'CDC_FACT_SHIPMENT',
        'RAW.SHIPMENTS',
        'SILVER.FACT_SHIPMENT',
        CURRENT_TIMESTAMP(),
        :V_CAPTURED,
        0, 0, 0,
        'RUNNING',
        :V_BATCH_IDS
    );

    MERGE INTO SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT T
    USING (
        WITH AFFECTED_KEYS AS (
            SELECT DISTINCT SHIPMENT_ID
            FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENTS
        ),
        LATEST_RAW AS (
            SELECT
                R.SHIPMENT_ID,
                R.SHIPMENT_TYPE,
                R.CARRIER_ID,
                R.ROUTE_ID,
                R.SHIPMENT_STATUS,
                R.PLANNED_DEPARTURE_AT,
                R.ACTUAL_DEPARTURE_AT,
                R.PLANNED_DELIVERY_AT,
                R.ACTUAL_DELIVERY_AT,
                R.SHIPPING_COST,
                R.LAST_UPDATED_AT,
                DATEDIFF(
                    'HOUR',
                    R.PLANNED_DEPARTURE_AT,
                    R.PLANNED_DELIVERY_AT
                ) AS PLANNED_TRANSIT_HOURS,
                CASE
                    WHEN R.ACTUAL_DEPARTURE_AT IS NULL
                      OR R.ACTUAL_DELIVERY_AT IS NULL
                    THEN NULL
                    ELSE DATEDIFF(
                        'HOUR',
                        R.ACTUAL_DEPARTURE_AT,
                        R.ACTUAL_DELIVERY_AT
                    )
                END AS ACTUAL_TRANSIT_HOURS,
                CASE
                    WHEN R.ACTUAL_DELIVERY_AT IS NULL THEN NULL
                    WHEN R.PLANNED_DELIVERY_AT IS NULL THEN NULL
                    ELSE R.ACTUAL_DELIVERY_AT <= R.PLANNED_DELIVERY_AT
                END AS IS_ON_TIME
            FROM SUPPLY_CHAIN_DW.RAW.SHIPMENTS R
            INNER JOIN AFFECTED_KEYS K
                ON R.SHIPMENT_ID = K.SHIPMENT_ID
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY R.SHIPMENT_ID
                ORDER BY
                    R.LAST_UPDATED_AT DESC,
                    R.LOADED_AT DESC,
                    R.SOURCE_BATCH_TS DESC
            ) = 1
        )
        SELECT * FROM LATEST_RAW
    ) S
       ON T.SHIPMENT_ID = S.SHIPMENT_ID

    WHEN MATCHED
         AND S.LAST_UPDATED_AT > T.LAST_UPDATED_AT
    THEN UPDATE SET
        T.SHIPMENT_TYPE        = S.SHIPMENT_TYPE,
        T.CARRIER_ID           = S.CARRIER_ID,
        T.ROUTE_ID             = S.ROUTE_ID,
        T.SHIPMENT_STATUS      = S.SHIPMENT_STATUS,
        T.PLANNED_DEPARTURE_AT = S.PLANNED_DEPARTURE_AT,
        T.ACTUAL_DEPARTURE_AT  = S.ACTUAL_DEPARTURE_AT,
        T.PLANNED_DELIVERY_AT  = S.PLANNED_DELIVERY_AT,
        T.ACTUAL_DELIVERY_AT   = S.ACTUAL_DELIVERY_AT,
        T.SHIPPING_COST        = S.SHIPPING_COST,
        T.PLANNED_TRANSIT_HOURS = S.PLANNED_TRANSIT_HOURS,
        T.ACTUAL_TRANSIT_HOURS  = S.ACTUAL_TRANSIT_HOURS,
        T.IS_ON_TIME           = S.IS_ON_TIME,
        T.LAST_UPDATED_AT      = S.LAST_UPDATED_AT

    WHEN NOT MATCHED
    THEN INSERT (
        SHIPMENT_ID,
        SHIPMENT_TYPE,
        CARRIER_ID,
        ROUTE_ID,
        SHIPMENT_STATUS,
        PLANNED_DEPARTURE_AT,
        ACTUAL_DEPARTURE_AT,
        PLANNED_DELIVERY_AT,
        ACTUAL_DELIVERY_AT,
        SHIPPING_COST,
        PLANNED_TRANSIT_HOURS,
        ACTUAL_TRANSIT_HOURS,
        IS_ON_TIME,
        LAST_UPDATED_AT
    )
    VALUES (
        S.SHIPMENT_ID,
        S.SHIPMENT_TYPE,
        S.CARRIER_ID,
        S.ROUTE_ID,
        S.SHIPMENT_STATUS,
        S.PLANNED_DEPARTURE_AT,
        S.ACTUAL_DEPARTURE_AT,
        S.PLANNED_DELIVERY_AT,
        S.ACTUAL_DELIVERY_AT,
        S.SHIPPING_COST,
        S.PLANNED_TRANSIT_HOURS,
        S.ACTUAL_TRANSIT_HOURS,
        S.IS_ON_TIME,
        S.LAST_UPDATED_AT
    );

    SELECT
        COALESCE("number of rows inserted", 0),
        COALESCE("number of rows updated", 0)
    INTO
        :V_INSERTED,
        :V_UPDATED
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    V_SKIPPED := GREATEST(V_CAPTURED - V_INSERTED - V_UPDATED, 0);

    UPDATE SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
       SET ROWS_INSERTED = :V_INSERTED,
           ROWS_UPDATED  = :V_UPDATED,
           ROWS_SKIPPED  = :V_SKIPPED,
           STATUS        = 'SUCCESS',
           COMPLETED_AT  = CURRENT_TIMESTAMP()
     WHERE RUN_ID = :V_RUN_ID;

    COMMIT;

    RETURN
        'SUCCESS | RUN_ID=' || V_RUN_ID ||
        ' | CAPTURED=' || V_CAPTURED ||
        ' | INSERTED=' || V_INSERTED ||
        ' | UPDATED=' || V_UPDATED ||
        ' | SKIPPED=' || V_SKIPPED;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;

        INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
            RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
            STARTED_AT, COMPLETED_AT, ROWS_CAPTURED,
            ROWS_INSERTED, ROWS_UPDATED, ROWS_SKIPPED,
            STATUS, ERROR_MESSAGE, LOAD_BATCH_IDS
        )
        VALUES (
            :V_RUN_ID,
            'CDC_FACT_SHIPMENT',
            'RAW.SHIPMENTS',
            'SILVER.FACT_SHIPMENT',
            CURRENT_TIMESTAMP(),
            CURRENT_TIMESTAMP(),
            :V_CAPTURED,
            0, 0, 0,
            'FAILED',
            SQLERRM,
            :V_BATCH_IDS
        );

        RAISE;
END;
$$;


-- =============================================================================
-- 5. FACT_SHIPMENT_LINE
-- RAW source: SHIPMENT_LINES
-- Grain: SHIPMENT_LINE_ID
-- Strategy: INSERT ONLY
-- =============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SHIPMENT_LINE()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID     VARCHAR DEFAULT UUID_STRING();
    V_CAPTURED   NUMBER  DEFAULT 0;
    V_INSERTED   NUMBER  DEFAULT 0;
    V_SKIPPED    NUMBER  DEFAULT 0;
    V_BATCH_IDS  VARCHAR DEFAULT NULL;
BEGIN

    SELECT
        COUNT(*),
        LISTAGG(DISTINCT LOAD_BATCH_ID, ',')
            WITHIN GROUP (ORDER BY LOAD_BATCH_ID)
    INTO
        :V_CAPTURED,
        :V_BATCH_IDS
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENT_LINES;

    IF (V_CAPTURED = 0) THEN
        RETURN 'NO_DATA';
    END IF;

    BEGIN TRANSACTION;

    INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
        RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
        STARTED_AT, ROWS_CAPTURED, ROWS_INSERTED,
        ROWS_UPDATED, ROWS_SKIPPED, STATUS, LOAD_BATCH_IDS
    )
    VALUES (
        :V_RUN_ID,
        'CDC_FACT_SHIPMENT_LINE',
        'RAW.SHIPMENT_LINES',
        'SILVER.FACT_SHIPMENT_LINE',
        CURRENT_TIMESTAMP(),
        :V_CAPTURED,
        0, 0, 0,
        'RUNNING',
        :V_BATCH_IDS
    );

    INSERT INTO SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE (
        SHIPMENT_LINE_ID,
        SHIPMENT_ID,
        ORDER_LINE_ID,
        PART_ID,
        SHIPPED_QTY,
        CREATED_AT
    )
    SELECT
        S.SHIPMENT_LINE_ID,
        S.SHIPMENT_ID,
        S.ORDER_LINE_ID,
        S.PART_ID,
        S.SHIPPED_QTY,
        S.CREATED_AT
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENT_LINES S
    WHERE NOT EXISTS (
        SELECT 1
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE T
        WHERE T.SHIPMENT_LINE_ID = S.SHIPMENT_LINE_ID
    )
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY S.SHIPMENT_LINE_ID
        ORDER BY
            S.LOADED_AT DESC,
            S.SOURCE_BATCH_TS DESC
    ) = 1;

    V_INSERTED := SQLROWCOUNT;
    V_SKIPPED  := GREATEST(V_CAPTURED - V_INSERTED, 0);

    UPDATE SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
       SET ROWS_INSERTED = :V_INSERTED,
           ROWS_UPDATED  = 0,
           ROWS_SKIPPED  = :V_SKIPPED,
           STATUS        = 'SUCCESS',
           COMPLETED_AT  = CURRENT_TIMESTAMP()
     WHERE RUN_ID = :V_RUN_ID;

    COMMIT;

    RETURN
        'SUCCESS | RUN_ID=' || V_RUN_ID ||
        ' | CAPTURED=' || V_CAPTURED ||
        ' | INSERTED=' || V_INSERTED ||
        ' | SKIPPED=' || V_SKIPPED;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;

        INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
            RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
            STARTED_AT, COMPLETED_AT, ROWS_CAPTURED,
            ROWS_INSERTED, ROWS_UPDATED, ROWS_SKIPPED,
            STATUS, ERROR_MESSAGE, LOAD_BATCH_IDS
        )
        VALUES (
            :V_RUN_ID,
            'CDC_FACT_SHIPMENT_LINE',
            'RAW.SHIPMENT_LINES',
            'SILVER.FACT_SHIPMENT_LINE',
            CURRENT_TIMESTAMP(),
            CURRENT_TIMESTAMP(),
            :V_CAPTURED,
            0, 0, 0,
            'FAILED',
            SQLERRM,
            :V_BATCH_IDS
        );

        RAISE;
END;
$$;


-- =============================================================================
-- 6. FACT_SHIPMENT_EVENT
-- RAW source: SHIPMENT_EVENTS
-- Grain: SHIPMENT_EVENT_ID
-- Strategy: INSERT ONLY
-- =============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_SHIPMENT_EVENT()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID     VARCHAR DEFAULT UUID_STRING();
    V_CAPTURED   NUMBER  DEFAULT 0;
    V_INSERTED   NUMBER  DEFAULT 0;
    V_SKIPPED    NUMBER  DEFAULT 0;
    V_BATCH_IDS  VARCHAR DEFAULT NULL;
BEGIN

    SELECT
        COUNT(*),
        LISTAGG(DISTINCT LOAD_BATCH_ID, ',')
            WITHIN GROUP (ORDER BY LOAD_BATCH_ID)
    INTO
        :V_CAPTURED,
        :V_BATCH_IDS
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENT_EVENTS;

    IF (V_CAPTURED = 0) THEN
        RETURN 'NO_DATA';
    END IF;

    BEGIN TRANSACTION;

    INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
        RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
        STARTED_AT, ROWS_CAPTURED, ROWS_INSERTED,
        ROWS_UPDATED, ROWS_SKIPPED, STATUS, LOAD_BATCH_IDS
    )
    VALUES (
        :V_RUN_ID,
        'CDC_FACT_SHIPMENT_EVENT',
        'RAW.SHIPMENT_EVENTS',
        'SILVER.FACT_SHIPMENT_EVENT',
        CURRENT_TIMESTAMP(),
        :V_CAPTURED,
        0, 0, 0,
        'RUNNING',
        :V_BATCH_IDS
    );

    INSERT INTO SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT (
        SHIPMENT_EVENT_ID,
        SHIPMENT_ID,
        EVENT_TIMESTAMP,
        EVENT_TYPE,
        LOCATION_LATITUDE,
        LOCATION_LONGITUDE,
        EVENT_DESCRIPTION
    )
    SELECT
        S.SHIPMENT_EVENT_ID,
        S.SHIPMENT_ID,
        S.EVENT_TIMESTAMP,
        S.EVENT_TYPE,
        S.LOCATION_LATITUDE,
        S.LOCATION_LONGITUDE,
        S.EVENT_DESCRIPTION
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_SHIPMENT_EVENTS S
    WHERE NOT EXISTS (
        SELECT 1
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT T
        WHERE T.SHIPMENT_EVENT_ID = S.SHIPMENT_EVENT_ID
    )
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY S.SHIPMENT_EVENT_ID
        ORDER BY
            S.LOADED_AT DESC,
            S.SOURCE_BATCH_TS DESC
    ) = 1;

    V_INSERTED := SQLROWCOUNT;
    V_SKIPPED  := GREATEST(V_CAPTURED - V_INSERTED, 0);

    UPDATE SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
       SET ROWS_INSERTED = :V_INSERTED,
           ROWS_UPDATED  = 0,
           ROWS_SKIPPED  = :V_SKIPPED,
           STATUS        = 'SUCCESS',
           COMPLETED_AT  = CURRENT_TIMESTAMP()
     WHERE RUN_ID = :V_RUN_ID;

    COMMIT;

    RETURN
        'SUCCESS | RUN_ID=' || V_RUN_ID ||
        ' | CAPTURED=' || V_CAPTURED ||
        ' | INSERTED=' || V_INSERTED ||
        ' | SKIPPED=' || V_SKIPPED;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;

        INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
            RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
            STARTED_AT, COMPLETED_AT, ROWS_CAPTURED,
            ROWS_INSERTED, ROWS_UPDATED, ROWS_SKIPPED,
            STATUS, ERROR_MESSAGE, LOAD_BATCH_IDS
        )
        VALUES (
            :V_RUN_ID,
            'CDC_FACT_SHIPMENT_EVENT',
            'RAW.SHIPMENT_EVENTS',
            'SILVER.FACT_SHIPMENT_EVENT',
            CURRENT_TIMESTAMP(),
            CURRENT_TIMESTAMP(),
            :V_CAPTURED,
            0, 0, 0,
            'FAILED',
            SQLERRM,
            :V_BATCH_IDS
        );

        RAISE;
END;
$$;


-- =============================================================================
-- 7. FACT_VEHICLE_TELEMETRY
-- RAW source: VEHICLE_TELEMETRY
-- Grain: TELEMETRY_ID
-- Strategy: INSERT ONLY
-- =============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_VEHICLE_TELEMETRY()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID     VARCHAR DEFAULT UUID_STRING();
    V_CAPTURED   NUMBER  DEFAULT 0;
    V_INSERTED   NUMBER  DEFAULT 0;
    V_SKIPPED    NUMBER  DEFAULT 0;
    V_BATCH_IDS  VARCHAR DEFAULT NULL;
BEGIN

    SELECT
        COUNT(*),
        LISTAGG(DISTINCT LOAD_BATCH_ID, ',')
            WITHIN GROUP (ORDER BY LOAD_BATCH_ID)
    INTO
        :V_CAPTURED,
        :V_BATCH_IDS
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_VEHICLE_TELEMETRY;

    IF (V_CAPTURED = 0) THEN
        RETURN 'NO_DATA';
    END IF;

    BEGIN TRANSACTION;

    INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
        RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
        STARTED_AT, ROWS_CAPTURED, ROWS_INSERTED,
        ROWS_UPDATED, ROWS_SKIPPED, STATUS, LOAD_BATCH_IDS
    )
    VALUES (
        :V_RUN_ID,
        'CDC_FACT_VEHICLE_TELEMETRY',
        'RAW.VEHICLE_TELEMETRY',
        'SILVER.FACT_VEHICLE_TELEMETRY',
        CURRENT_TIMESTAMP(),
        :V_CAPTURED,
        0, 0, 0,
        'RUNNING',
        :V_BATCH_IDS
    );

    INSERT INTO SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY (
        TELEMETRY_ID,
        VEHICLE_ID,
        SHIPMENT_ID,
        EVENT_TIMESTAMP,
        LATITUDE,
        LONGITUDE,
        SPEED_KMPH,
        VEHICLE_STATUS,
        DISTANCE_TRAVELLED_KM
    )
    SELECT
        S.TELEMETRY_ID,
        S.VEHICLE_ID,
        S.SHIPMENT_ID,
        S.EVENT_TIMESTAMP,
        S.LATITUDE,
        S.LONGITUDE,
        S.SPEED_KMPH,
        S.VEHICLE_STATUS,
        S.DISTANCE_TRAVELLED_KM
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_VEHICLE_TELEMETRY S
    WHERE NOT EXISTS (
        SELECT 1
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY T
        WHERE T.TELEMETRY_ID = S.TELEMETRY_ID
    )
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY S.TELEMETRY_ID
        ORDER BY
            S.LOADED_AT DESC,
            S.SOURCE_BATCH_TS DESC
    ) = 1;

    V_INSERTED := SQLROWCOUNT;
    V_SKIPPED  := GREATEST(V_CAPTURED - V_INSERTED, 0);

    UPDATE SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
       SET ROWS_INSERTED = :V_INSERTED,
           ROWS_UPDATED  = 0,
           ROWS_SKIPPED  = :V_SKIPPED,
           STATUS        = 'SUCCESS',
           COMPLETED_AT  = CURRENT_TIMESTAMP()
     WHERE RUN_ID = :V_RUN_ID;

    COMMIT;

    RETURN
        'SUCCESS | RUN_ID=' || V_RUN_ID ||
        ' | CAPTURED=' || V_CAPTURED ||
        ' | INSERTED=' || V_INSERTED ||
        ' | SKIPPED=' || V_SKIPPED;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;

        INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
            RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
            STARTED_AT, COMPLETED_AT, ROWS_CAPTURED,
            ROWS_INSERTED, ROWS_UPDATED, ROWS_SKIPPED,
            STATUS, ERROR_MESSAGE, LOAD_BATCH_IDS
        )
        VALUES (
            :V_RUN_ID,
            'CDC_FACT_VEHICLE_TELEMETRY',
            'RAW.VEHICLE_TELEMETRY',
            'SILVER.FACT_VEHICLE_TELEMETRY',
            CURRENT_TIMESTAMP(),
            CURRENT_TIMESTAMP(),
            :V_CAPTURED,
            0, 0, 0,
            'FAILED',
            SQLERRM,
            :V_BATCH_IDS
        );

        RAISE;
END;
$$;


-- =============================================================================
-- 8. FACT_ORDER_LINE
-- RAW sources: ORDERS + ORDER_LINES
-- Grain: ORDER_LINE_ID
-- Strategy: dual-stream targeted MERGE
--
-- Parent ORDER change:
--   recompute all lines belonging to that ORDER_ID.
--
-- ORDER_LINE change:
--   recompute that line using latest parent ORDER + latest line version.
--
-- Both Streams are referenced by the same MERGE, so their offsets advance
-- atomically with the Silver write.
-- =============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_DW.CONTROL.SP_CDC_FACT_ORDER_LINE()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID          VARCHAR DEFAULT UUID_STRING();
    V_ORDER_CAPTURED  NUMBER  DEFAULT 0;
    V_LINE_CAPTURED   NUMBER  DEFAULT 0;
    V_CAPTURED        NUMBER  DEFAULT 0;
    V_SOURCE_ROWS     NUMBER  DEFAULT 0;
    V_INSERTED        NUMBER  DEFAULT 0;
    V_UPDATED         NUMBER  DEFAULT 0;
    V_SKIPPED         NUMBER  DEFAULT 0;
    V_BATCH_IDS       VARCHAR DEFAULT NULL;
BEGIN

    SELECT COUNT(*)
      INTO :V_ORDER_CAPTURED
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDERS;

    SELECT COUNT(*)
      INTO :V_LINE_CAPTURED
    FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDER_LINES;

    V_CAPTURED := V_ORDER_CAPTURED + V_LINE_CAPTURED;

    IF (V_CAPTURED = 0) THEN
        RETURN 'NO_DATA';
    END IF;

    SELECT LISTAGG(DISTINCT LOAD_BATCH_ID, ',')
               WITHIN GROUP (ORDER BY LOAD_BATCH_ID)
      INTO :V_BATCH_IDS
    FROM (
        SELECT LOAD_BATCH_ID
        FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDERS

        UNION ALL

        SELECT LOAD_BATCH_ID
        FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDER_LINES
    );

    -- Count how many Silver business rows are in the recomputation set.
    -- This is different from stream rows because one parent ORDER update can
    -- cause multiple child ORDER_LINE rows to be recomputed.
    SELECT COUNT(*)
      INTO :V_SOURCE_ROWS
    FROM (
        WITH CHANGED_ORDERS AS (
            SELECT DISTINCT ORDER_ID
            FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDERS
        ),
        CHANGED_LINES AS (
            SELECT DISTINCT ORDER_LINE_ID, ORDER_ID
            FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDER_LINES
        ),
        AFFECTED_ORDERS AS (
            SELECT ORDER_ID FROM CHANGED_ORDERS
            UNION
            SELECT ORDER_ID FROM CHANGED_LINES
        ),
        AFFECTED_LINES AS (
            SELECT ORDER_LINE_ID FROM CHANGED_LINES
            UNION
            SELECT DISTINCT R.ORDER_LINE_ID
            FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES R
            INNER JOIN CHANGED_ORDERS C
                ON R.ORDER_ID = C.ORDER_ID
        ),
        LATEST_ORDERS AS (
            SELECT R.*
            FROM SUPPLY_CHAIN_DW.RAW.ORDERS R
            INNER JOIN AFFECTED_ORDERS A
                ON R.ORDER_ID = A.ORDER_ID
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY R.ORDER_ID
                ORDER BY
                    R.LAST_UPDATED_AT DESC,
                    R.LOADED_AT DESC,
                    R.SOURCE_BATCH_TS DESC
            ) = 1
        ),
        LATEST_LINES AS (
            SELECT R.*
            FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES R
            INNER JOIN AFFECTED_LINES A
                ON R.ORDER_LINE_ID = A.ORDER_LINE_ID
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY R.ORDER_LINE_ID
                ORDER BY
                    R.LAST_UPDATED_AT DESC,
                    R.LOADED_AT DESC,
                    R.SOURCE_BATCH_TS DESC
            ) = 1
        )
        SELECT L.ORDER_LINE_ID
        FROM LATEST_LINES L
        INNER JOIN LATEST_ORDERS O
            ON L.ORDER_ID = O.ORDER_ID
    );

    BEGIN TRANSACTION;

    INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
        RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
        STARTED_AT, ROWS_CAPTURED, ROWS_INSERTED,
        ROWS_UPDATED, ROWS_SKIPPED, STATUS, LOAD_BATCH_IDS
    )
    VALUES (
        :V_RUN_ID,
        'CDC_FACT_ORDER_LINE',
        'RAW.ORDERS + RAW.ORDER_LINES',
        'SILVER.FACT_ORDER_LINE',
        CURRENT_TIMESTAMP(),
        :V_CAPTURED,
        0, 0, 0,
        'RUNNING',
        :V_BATCH_IDS
    );

    MERGE INTO SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE T
    USING (
        WITH CHANGED_ORDERS AS (
            SELECT DISTINCT ORDER_ID
            FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDERS
        ),
        CHANGED_LINES AS (
            SELECT DISTINCT ORDER_LINE_ID, ORDER_ID
            FROM SUPPLY_CHAIN_DW.RAW.STRM_RAW_ORDER_LINES
        ),
        AFFECTED_ORDERS AS (
            SELECT ORDER_ID FROM CHANGED_ORDERS
            UNION
            SELECT ORDER_ID FROM CHANGED_LINES
        ),
        AFFECTED_LINES AS (
            SELECT ORDER_LINE_ID FROM CHANGED_LINES

            UNION

            SELECT DISTINCT R.ORDER_LINE_ID
            FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES R
            INNER JOIN CHANGED_ORDERS C
                ON R.ORDER_ID = C.ORDER_ID
        ),
        LATEST_ORDERS AS (
            SELECT R.*
            FROM SUPPLY_CHAIN_DW.RAW.ORDERS R
            INNER JOIN AFFECTED_ORDERS A
                ON R.ORDER_ID = A.ORDER_ID
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY R.ORDER_ID
                ORDER BY
                    R.LAST_UPDATED_AT DESC,
                    R.LOADED_AT DESC,
                    R.SOURCE_BATCH_TS DESC
            ) = 1
        ),
        LATEST_LINES AS (
            SELECT R.*
            FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES R
            INNER JOIN AFFECTED_LINES A
                ON R.ORDER_LINE_ID = A.ORDER_LINE_ID
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY R.ORDER_LINE_ID
                ORDER BY
                    R.LAST_UPDATED_AT DESC,
                    R.LOADED_AT DESC,
                    R.SOURCE_BATCH_TS DESC
            ) = 1
        )
        SELECT
            L.ORDER_LINE_ID,
            L.ORDER_ID,
            O.CUSTOMER_ID,
            O.PLANT_ID,
            L.PART_ID,
            O.ORDER_DATE::DATE AS ORDER_DATE_KEY,
            O.REQUESTED_DELIVERY_DATE AS REQUESTED_DELIVERY_DATE_KEY,
            O.ORDER_STATUS,
            L.LINE_STATUS,
            L.ORDERED_QTY,
            L.UNIT_PRICE,
            L.LINE_AMOUNT,
            O.LAST_UPDATED_AT AS ORDER_UPDATED_AT,
            L.LAST_UPDATED_AT AS LINE_UPDATED_AT
        FROM LATEST_LINES L
        INNER JOIN LATEST_ORDERS O
            ON L.ORDER_ID = O.ORDER_ID
    ) S
       ON T.ORDER_LINE_ID = S.ORDER_LINE_ID

    WHEN MATCHED
         AND (
                S.LINE_UPDATED_AT  > T.LINE_UPDATED_AT
             OR S.ORDER_UPDATED_AT > T.ORDER_UPDATED_AT
         )
    THEN UPDATE SET
        T.ORDER_ID                    = S.ORDER_ID,
        T.CUSTOMER_ID                 = S.CUSTOMER_ID,
        T.PLANT_ID                    = S.PLANT_ID,
        T.PART_ID                     = S.PART_ID,
        T.ORDER_DATE_KEY               = S.ORDER_DATE_KEY,
        T.REQUESTED_DELIVERY_DATE_KEY  = S.REQUESTED_DELIVERY_DATE_KEY,
        T.ORDER_STATUS                 = S.ORDER_STATUS,
        T.LINE_STATUS                  = S.LINE_STATUS,
        T.ORDERED_QTY                  = S.ORDERED_QTY,
        T.UNIT_PRICE                   = S.UNIT_PRICE,
        T.LINE_AMOUNT                  = S.LINE_AMOUNT,
        T.ORDER_UPDATED_AT             = S.ORDER_UPDATED_AT,
        T.LINE_UPDATED_AT              = S.LINE_UPDATED_AT

    WHEN NOT MATCHED
    THEN INSERT (
        ORDER_LINE_ID,
        ORDER_ID,
        CUSTOMER_ID,
        PLANT_ID,
        PART_ID,
        ORDER_DATE_KEY,
        REQUESTED_DELIVERY_DATE_KEY,
        ORDER_STATUS,
        LINE_STATUS,
        ORDERED_QTY,
        UNIT_PRICE,
        LINE_AMOUNT,
        ORDER_UPDATED_AT,
        LINE_UPDATED_AT
    )
    VALUES (
        S.ORDER_LINE_ID,
        S.ORDER_ID,
        S.CUSTOMER_ID,
        S.PLANT_ID,
        S.PART_ID,
        S.ORDER_DATE_KEY,
        S.REQUESTED_DELIVERY_DATE_KEY,
        S.ORDER_STATUS,
        S.LINE_STATUS,
        S.ORDERED_QTY,
        S.UNIT_PRICE,
        S.LINE_AMOUNT,
        S.ORDER_UPDATED_AT,
        S.LINE_UPDATED_AT
    );

    SELECT
        COALESCE("number of rows inserted", 0),
        COALESCE("number of rows updated", 0)
    INTO
        :V_INSERTED,
        :V_UPDATED
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    V_SKIPPED := GREATEST(V_SOURCE_ROWS - V_INSERTED - V_UPDATED, 0);

    UPDATE SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG
       SET ROWS_INSERTED = :V_INSERTED,
           ROWS_UPDATED  = :V_UPDATED,
           ROWS_SKIPPED  = :V_SKIPPED,
           STATUS        = 'SUCCESS',
           COMPLETED_AT  = CURRENT_TIMESTAMP()
     WHERE RUN_ID = :V_RUN_ID;

    COMMIT;

    RETURN
        'SUCCESS | RUN_ID=' || V_RUN_ID ||
        ' | STREAM_ROWS=' || V_CAPTURED ||
        ' | SOURCE_ROWS=' || V_SOURCE_ROWS ||
        ' | INSERTED=' || V_INSERTED ||
        ' | UPDATED=' || V_UPDATED ||
        ' | SKIPPED=' || V_SKIPPED;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;

        INSERT INTO SUPPLY_CHAIN_DW.CONTROL.CDC_STREAM_RUN_LOG (
            RUN_ID, PIPELINE_NAME, SOURCE_TABLE, TARGET_TABLE,
            STARTED_AT, COMPLETED_AT, ROWS_CAPTURED,
            ROWS_INSERTED, ROWS_UPDATED, ROWS_SKIPPED,
            STATUS, ERROR_MESSAGE, LOAD_BATCH_IDS
        )
        VALUES (
            :V_RUN_ID,
            'CDC_FACT_ORDER_LINE',
            'RAW.ORDERS + RAW.ORDER_LINES',
            'SILVER.FACT_ORDER_LINE',
            CURRENT_TIMESTAMP(),
            CURRENT_TIMESTAMP(),
            :V_CAPTURED,
            0, 0, 0,
            'FAILED',
            SQLERRM,
            :V_BATCH_IDS
        );

        RAISE;
END;
$$;


-- =============================================================================
-- End V3.10.0
-- =============================================================================
