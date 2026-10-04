-- =============================================================================
-- V2.6.0 — Create MART_LOGISTICS_PERFORMANCE
-- =============================================================================
--
-- ## Change purpose
-- Fourth Gold analytical mart: shipment-level logistics performance.
-- Provides delivery performance, delay metrics, route/carrier context,
-- and disruption evidence for every shipment.
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
--
-- ## Grain
-- One row per SHIPMENT_ID (60,000 expected rows)
--
-- ## Design reference
-- 29-column v2 contract. Two pre-aggregation branches (events, order impact)
-- plus dimension enrichment.
--
-- ## Preconditions
-- V2.0.0 (GOLD schema) must be applied.
-- Silver baseline tables must exist in SUPPLY_CHAIN_DW.SILVER.
--
-- ## DDL

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE AS

WITH analysis_anchor AS (
    -- Deterministic analysis date from FACT_SHIPMENT.
    SELECT MAX(LAST_UPDATED_AT)::DATE AS ANALYSIS_AS_OF_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT
),

-- =============================================================================
-- BRANCH 1: Shipment Event Aggregation → SHIPMENT_ID
-- Source grain: SHIPMENT_EVENT_ID (181,725 rows)
-- Target grain: SHIPMENT_ID (60,000 rows — every shipment has >= 1 event)
-- =============================================================================
event_agg AS (
    SELECT
        SHIPMENT_ID,
        SUM(CASE WHEN EVENT_TYPE = 'ROUTE_DEVIATION' THEN 1 ELSE 0 END)
            AS ROUTE_DEVIATION_EVENT_COUNT,
        SUM(CASE WHEN EVENT_TYPE = 'DELAY_REPORTED' THEN 1 ELSE 0 END)
            AS DELAY_REPORTED_EVENT_COUNT
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT
    GROUP BY SHIPMENT_ID
),

-- =============================================================================
-- BRANCH 2: Order Impact → SHIPMENT_ID
-- Source: FACT_SHIPMENT_LINE → FACT_ORDER_LINE (for ORDER_ID)
-- Target grain: SHIPMENT_ID (60,000 rows)
-- =============================================================================
order_impact AS (
    SELECT
        fsl.SHIPMENT_ID,
        COUNT(DISTINCT fol.ORDER_ID) AS DISTINCT_ORDER_COUNT
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE fsl
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE fol
        ON fsl.ORDER_LINE_ID = fol.ORDER_LINE_ID
    GROUP BY fsl.SHIPMENT_ID
)

-- =============================================================================
-- FINAL ASSEMBLY
-- FACT_SHIPMENT (60,000 rows) + Branch 1 + Branch 2 + DIM_CARRIER + DIM_ROUTE
-- All joins are 1:1 or M:1 on SHIPMENT_ID grain.
-- =============================================================================
SELECT
    -- 1. Metadata / Identifiers
    fs.SHIPMENT_ID,
    a.ANALYSIS_AS_OF_DATE,

    -- 2. Shipment Attributes
    fs.SHIPMENT_TYPE,
    fs.SHIPMENT_STATUS,
    fs.CARRIER_ID,
    fs.ROUTE_ID,

    -- 3. Carrier Attributes
    dc.CARRIER_NAME,
    dc.CARRIER_TYPE,
    dc.SERVICE_LEVEL,

    -- 4. Route Attributes
    dr.ORIGIN_TYPE,
    dr.ORIGIN_ID,
    dr.DESTINATION_TYPE,
    dr.DESTINATION_ID,
    dr.DISTANCE_KM,
    dr.ROUTE_RISK_LEVEL,

    -- 5. Timestamps
    fs.PLANNED_DEPARTURE_AT,
    fs.ACTUAL_DEPARTURE_AT,
    fs.PLANNED_DELIVERY_AT,
    fs.ACTUAL_DELIVERY_AT,

    -- 6. Cost & On-Time
    fs.SHIPPING_COST,
    fs.IS_ON_TIME,

    -- 7. Transit & Delay Metrics
    fs.PLANNED_TRANSIT_HOURS,
    fs.ACTUAL_TRANSIT_HOURS,
    CASE WHEN fs.ACTUAL_TRANSIT_HOURS IS NOT NULL AND fs.PLANNED_TRANSIT_HOURS IS NOT NULL
         THEN fs.ACTUAL_TRANSIT_HOURS - fs.PLANNED_TRANSIT_HOURS
    END AS TRANSIT_VARIANCE_HOURS,
    CASE WHEN fs.ACTUAL_DEPARTURE_AT IS NOT NULL AND fs.PLANNED_DEPARTURE_AT IS NOT NULL
         THEN DATEDIFF('HOUR', fs.PLANNED_DEPARTURE_AT, fs.ACTUAL_DEPARTURE_AT)
    END AS DEPARTURE_DELAY_HOURS,
    CASE WHEN fs.ACTUAL_DELIVERY_AT IS NOT NULL AND fs.PLANNED_DELIVERY_AT IS NOT NULL
         THEN DATEDIFF('HOUR', fs.PLANNED_DELIVERY_AT, fs.ACTUAL_DELIVERY_AT)
    END AS DELIVERY_DELAY_HOURS,

    -- 8. Event Metrics
    COALESCE(ea.ROUTE_DEVIATION_EVENT_COUNT, 0) AS ROUTE_DEVIATION_EVENT_COUNT,
    COALESCE(ea.DELAY_REPORTED_EVENT_COUNT, 0)  AS DELAY_REPORTED_EVENT_COUNT,

    -- 9. Order Impact
    COALESCE(oi.DISTINCT_ORDER_COUNT, 0)        AS DISTINCT_ORDER_COUNT

FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT fs
CROSS JOIN analysis_anchor a
LEFT JOIN event_agg ea
    ON fs.SHIPMENT_ID = ea.SHIPMENT_ID
LEFT JOIN order_impact oi
    ON fs.SHIPMENT_ID = oi.SHIPMENT_ID
LEFT JOIN SUPPLY_CHAIN_DW.SILVER.DIM_CARRIER dc
    ON fs.CARRIER_ID = dc.CARRIER_ID
LEFT JOIN SUPPLY_CHAIN_DW.SILVER.DIM_ROUTE dr
    ON fs.ROUTE_ID = dr.ROUTE_ID;

-- ## Post-change validation
-- Run validations/gold/mart_logistics_performance_checks.sql
-- Run validations/gold/mart_logistics_performance_scenario_structural.sql
-- Run validations/gold/mart_logistics_performance_scenario_behavioral.sql

-- ## Rollback / manual recovery
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE;
