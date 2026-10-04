-- =============================================================================
-- V3.16.0 — Convert MART_LOGISTICS_PERFORMANCE to a Dynamic Table
-- =============================================================================
--
-- Change purpose
--   Replace the existing static GOLD.MART_LOGISTICS_PERFORMANCE table with a
--   Snowflake Dynamic Table while preserving:
--     * the existing object name,
--     * SHIPMENT_ID grain,
--     * the existing Gold business logic,
--     * existing downstream references such as SV_LOGISTICS_PERFORMANCE.
--
-- Why a NEW migration instead of editing V2.6.0
--   V2.6.0 is an already-versioned schema migration and must remain immutable.
--   This migration performs the later object-type change explicitly.
--
-- Refresh design
--   TARGET_LAG   = '5 minutes'
--   WAREHOUSE    = COMPUTE_WH
--   REFRESH_MODE = AUTO
--
-- AUTO is intentional for the first Dynamic Table conversion:
--   Snowflake will use incremental refresh when the definition is eligible,
--   otherwise it can fall back to full refresh. The post-change SHOW statement
--   exposes the resolved refresh mode so we can verify it after deployment.
--
-- Migration strategy
--   1. Create a temporary-name Dynamic Table from SILVER.
--   2. Validate that it initializes.
--   3. Drop the old static mart.
--   4. Rename the Dynamic Table to MART_LOGISTICS_PERFORMANCE.
--
-- This avoids dropping the existing mart before the Dynamic Table definition
-- has successfully compiled and initialized.
--
-- Preconditions
--   * SUPPLY_CHAIN_DW.GOLD exists.
--   * SILVER source tables exist.
--   * COMPUTE_WH exists and is usable by the migration role.
--   * Existing MART_LOGISTICS_PERFORMANCE is a TABLE from V2.6.0.
--
-- Grain
--   One row per SHIPMENT_ID.
-- =============================================================================

USE DATABASE SUPPLY_CHAIN_DW;
USE SCHEMA GOLD;


-- =============================================================================
-- 1. Build the replacement Dynamic Table under a temporary migration name
-- =============================================================================

CREATE OR REPLACE DYNAMIC TABLE
    SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE_DT_MIGRATION
    TARGET_LAG = '5 minutes'
    WAREHOUSE = COMPUTE_WH
    REFRESH_MODE = AUTO
    INITIALIZE = ON_CREATE
AS

WITH analysis_anchor AS (
    SELECT
        MAX(LAST_UPDATED_AT)::DATE AS ANALYSIS_AS_OF_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT
),

-- -----------------------------------------------------------------------------
-- Branch 1: shipment events -> SHIPMENT_ID
-- -----------------------------------------------------------------------------
event_agg AS (
    SELECT
        SHIPMENT_ID,
        COUNT(*) AS EVENT_COUNT,
        SUM(
            CASE
                WHEN EVENT_TYPE = 'ROUTE_DEVIATION' THEN 1
                ELSE 0
            END
        ) AS ROUTE_DEVIATION_EVENT_COUNT,
        SUM(
            CASE
                WHEN EVENT_TYPE = 'DELAY_REPORTED' THEN 1
                ELSE 0
            END
        ) AS DELAY_REPORTED_EVENT_COUNT,
        MAX(EVENT_TIMESTAMP) AS LATEST_EVENT_TIMESTAMP
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT
    GROUP BY SHIPMENT_ID
),

-- -----------------------------------------------------------------------------
-- Branch 2: vehicle telemetry -> SHIPMENT_ID
-- -----------------------------------------------------------------------------
telemetry_agg AS (
    SELECT
        SHIPMENT_ID,
        COUNT(*) AS TELEMETRY_POINT_COUNT,
        SUM(
            CASE
                WHEN VEHICLE_STATUS = 'OFF_ROUTE' THEN 1
                ELSE 0
            END
        ) AS OFF_ROUTE_POINT_COUNT,
        MAX(EVENT_TIMESTAMP) AS LATEST_TELEMETRY_TIMESTAMP
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY
    GROUP BY SHIPMENT_ID
),

-- -----------------------------------------------------------------------------
-- Branch 3: shipment-line/order impact -> SHIPMENT_ID
-- Aggregate before joining to the base shipment grain to prevent fan-out.
-- -----------------------------------------------------------------------------
order_impact AS (
    SELECT
        fsl.SHIPMENT_ID,
        COUNT(DISTINCT fsl.ORDER_LINE_ID) AS DISTINCT_ORDER_LINE_COUNT,
        COUNT(DISTINCT fol.ORDER_ID)      AS DISTINCT_ORDER_COUNT
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE fsl
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE fol
        ON fsl.ORDER_LINE_ID = fol.ORDER_LINE_ID
    GROUP BY fsl.SHIPMENT_ID
)

SELECT
    -- -------------------------------------------------------------------------
    -- Metadata / identifiers
    -- -------------------------------------------------------------------------
    fs.SHIPMENT_ID,
    aa.ANALYSIS_AS_OF_DATE,

    -- -------------------------------------------------------------------------
    -- Shipment attributes
    -- -------------------------------------------------------------------------
    fs.SHIPMENT_TYPE,
    fs.SHIPMENT_STATUS,
    fs.CARRIER_ID,
    fs.ROUTE_ID,
    fs.SHIPPING_COST,
    fs.IS_ON_TIME,

    -- -------------------------------------------------------------------------
    -- Carrier attributes
    -- -------------------------------------------------------------------------
    dc.CARRIER_NAME,
    dc.CARRIER_TYPE,
    dc.SERVICE_LEVEL,

    -- -------------------------------------------------------------------------
    -- Route attributes
    -- -------------------------------------------------------------------------
    dr.ORIGIN_TYPE,
    dr.ORIGIN_ID,
    dr.DESTINATION_TYPE,
    dr.DESTINATION_ID,
    dr.DISTANCE_KM,
    dr.ROUTE_RISK_LEVEL,

    -- -------------------------------------------------------------------------
    -- Shipment timestamps
    -- -------------------------------------------------------------------------
    fs.PLANNED_DEPARTURE_AT,
    fs.ACTUAL_DEPARTURE_AT,
    fs.PLANNED_DELIVERY_AT,
    fs.ACTUAL_DELIVERY_AT,

    -- -------------------------------------------------------------------------
    -- Transit / delay metrics
    -- -------------------------------------------------------------------------
    fs.PLANNED_TRANSIT_HOURS,
    fs.ACTUAL_TRANSIT_HOURS,

    CASE
        WHEN fs.ACTUAL_TRANSIT_HOURS IS NOT NULL
         AND fs.PLANNED_TRANSIT_HOURS IS NOT NULL
        THEN fs.ACTUAL_TRANSIT_HOURS - fs.PLANNED_TRANSIT_HOURS
        ELSE NULL
    END AS TRANSIT_VARIANCE_HOURS,

    CASE
        WHEN fs.ACTUAL_DELIVERY_AT IS NOT NULL
         AND fs.PLANNED_DELIVERY_AT IS NOT NULL
        THEN DATEDIFF(
            'HOUR',
            fs.PLANNED_DELIVERY_AT,
            fs.ACTUAL_DELIVERY_AT
        )
        ELSE NULL
    END AS DELIVERY_DELAY_HOURS,

    CASE
        WHEN fs.ACTUAL_DEPARTURE_AT IS NOT NULL
         AND fs.PLANNED_DEPARTURE_AT IS NOT NULL
        THEN DATEDIFF(
            'HOUR',
            fs.PLANNED_DEPARTURE_AT,
            fs.ACTUAL_DEPARTURE_AT
        )
        ELSE NULL
    END AS DEPARTURE_DELAY_HOURS,

    (fs.IS_ON_TIME IS NOT NULL) AS IS_DELIVERY_EVALUATED,

    -- -------------------------------------------------------------------------
    -- Event metrics
    -- -------------------------------------------------------------------------
    COALESCE(ea.EVENT_COUNT, 0) AS EVENT_COUNT,
    COALESCE(ea.ROUTE_DEVIATION_EVENT_COUNT, 0)
        AS ROUTE_DEVIATION_EVENT_COUNT,
    COALESCE(ea.DELAY_REPORTED_EVENT_COUNT, 0)
        AS DELAY_REPORTED_EVENT_COUNT,
    ea.LATEST_EVENT_TIMESTAMP,

    -- -------------------------------------------------------------------------
    -- Telemetry metrics
    -- -------------------------------------------------------------------------
    COALESCE(ta.TELEMETRY_POINT_COUNT, 0)
        AS TELEMETRY_POINT_COUNT,
    COALESCE(ta.OFF_ROUTE_POINT_COUNT, 0)
        AS OFF_ROUTE_POINT_COUNT,
    ta.LATEST_TELEMETRY_TIMESTAMP,

    -- -------------------------------------------------------------------------
    -- Order impact
    -- -------------------------------------------------------------------------
    COALESCE(oi.DISTINCT_ORDER_COUNT, 0)
        AS DISTINCT_ORDER_COUNT,
    COALESCE(oi.DISTINCT_ORDER_LINE_COUNT, 0)
        AS DISTINCT_ORDER_LINE_COUNT,

    -- -------------------------------------------------------------------------
    -- Explainability flags
    -- -------------------------------------------------------------------------
    (fs.IS_ON_TIME = FALSE) AS IS_LATE,

    (COALESCE(ea.ROUTE_DEVIATION_EVENT_COUNT, 0) > 0)
        AS HAS_ROUTE_DEVIATION,

    (COALESCE(ea.DELAY_REPORTED_EVENT_COUNT, 0) > 0)
        AS HAS_DELAY_REPORT,

    (COALESCE(ta.TELEMETRY_POINT_COUNT, 0) > 0)
        AS HAS_TELEMETRY

FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT fs

CROSS JOIN analysis_anchor aa

LEFT JOIN event_agg ea
    ON fs.SHIPMENT_ID = ea.SHIPMENT_ID

LEFT JOIN telemetry_agg ta
    ON fs.SHIPMENT_ID = ta.SHIPMENT_ID

LEFT JOIN order_impact oi
    ON fs.SHIPMENT_ID = oi.SHIPMENT_ID

LEFT JOIN SUPPLY_CHAIN_DW.SILVER.DIM_CARRIER dc
    ON fs.CARRIER_ID = dc.CARRIER_ID

LEFT JOIN SUPPLY_CHAIN_DW.SILVER.DIM_ROUTE dr
    ON fs.ROUTE_ID = dr.ROUTE_ID
;


-- =============================================================================
-- 2. Pre-swap validation
-- =============================================================================
-- These statements deliberately fail deployment if the replacement object
-- cannot be described. Row/grain checks are surfaced for inspection.
-- =============================================================================

DESCRIBE DYNAMIC TABLE
    SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE_DT_MIGRATION;

SELECT
    COUNT(*) AS ROW_COUNT,
    COUNT(DISTINCT SHIPMENT_ID) AS DISTINCT_SHIPMENT_COUNT,
    COUNT_IF(SHIPMENT_ID IS NULL) AS NULL_SHIPMENT_ID_COUNT
FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE_DT_MIGRATION;

SELECT
    SHIPMENT_ID,
    COUNT(*) AS ROW_COUNT
FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE_DT_MIGRATION
GROUP BY SHIPMENT_ID
HAVING COUNT(*) > 1;


-- =============================================================================
-- 3. Replace the previous static Gold mart while preserving its public name
-- =============================================================================
-- The existing semantic layer continues to refer to:
--   SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
-- so no semantic-view source-name change is required.
-- =============================================================================

DROP TABLE IF EXISTS
    SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE;

ALTER DYNAMIC TABLE
    SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE_DT_MIGRATION
    RENAME TO MART_LOGISTICS_PERFORMANCE;


-- =============================================================================
-- 4. Post-change validation
-- =============================================================================

DESCRIBE DYNAMIC TABLE
    SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE;

SHOW DYNAMIC TABLES LIKE 'MART_LOGISTICS_PERFORMANCE'
    IN SCHEMA SUPPLY_CHAIN_DW.GOLD;

-- Expected structural checks:
--   * one row per SHIPMENT_ID
--   * zero NULL SHIPMENT_ID values
--   * 40 columns
--   * downstream semantic view keeps the same Gold source name
--
-- After deployment, inspect SHOW DYNAMIC TABLES:
--   REFRESH_MODE / REFRESH_MODE_REASON shows whether AUTO resolved to
--   incremental or full refresh in the target Snowflake account.


-- =============================================================================
-- Rollback / manual recovery
-- =============================================================================
-- This migration intentionally does not rewrite V2.6.0.
-- If rollback is required:
--   1. DROP DYNAMIC TABLE SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE;
--   2. Re-run the original V2.6.0 mart SELECT manually as a TABLE only for
--      emergency recovery. Do not modify the committed V2.6.0 migration.
-- =============================================================================
