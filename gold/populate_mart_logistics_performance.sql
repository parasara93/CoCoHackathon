-- =============================================================================
-- Populate MART_LOGISTICS_PERFORMANCE
-- =============================================================================
-- Populates SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE from Silver sources.
-- Reuses archived V2.6.0 design (29 columns).
--
-- Two pre-aggregation branches (event counts, order impact) plus dimension
-- enrichment on a FACT_SHIPMENT base.
--
-- Prerequisites: V3.3.0 (empty table) must be deployed.
-- Idempotent: TRUNCATE + INSERT pattern.
-- =============================================================================

TRUNCATE TABLE SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE;

INSERT INTO SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE (
    SHIPMENT_ID, ANALYSIS_AS_OF_DATE,
    SHIPMENT_TYPE, SHIPMENT_STATUS, CARRIER_ID, ROUTE_ID,
    CARRIER_NAME, CARRIER_TYPE, SERVICE_LEVEL,
    ORIGIN_TYPE, ORIGIN_ID, DESTINATION_TYPE, DESTINATION_ID, DISTANCE_KM, ROUTE_RISK_LEVEL,
    PLANNED_DEPARTURE_AT, ACTUAL_DEPARTURE_AT, PLANNED_DELIVERY_AT, ACTUAL_DELIVERY_AT,
    SHIPPING_COST, IS_ON_TIME,
    PLANNED_TRANSIT_HOURS, ACTUAL_TRANSIT_HOURS, TRANSIT_VARIANCE_HOURS,
    DEPARTURE_DELAY_HOURS, DELIVERY_DELAY_HOURS,
    ROUTE_DEVIATION_EVENT_COUNT, DELAY_REPORTED_EVENT_COUNT,
    DISTINCT_ORDER_COUNT
)
WITH analysis_anchor AS (
    SELECT MAX(LAST_UPDATED_AT)::DATE AS ANALYSIS_AS_OF_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT
),

-- =========================================================================
-- BRANCH 1: Shipment Event Aggregation → SHIPMENT_ID
-- Source: FACT_SHIPMENT_EVENT (multiple events per shipment)
-- Fan-out prevention: GROUP BY SHIPMENT_ID with conditional SUM.
--   Collapses to exactly 1 row per SHIPMENT_ID.
-- =========================================================================
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

-- =========================================================================
-- BRANCH 2: Order Impact → SHIPMENT_ID
-- Source: FACT_SHIPMENT_LINE JOIN FACT_ORDER_LINE (M:1 on ORDER_LINE_ID)
-- Fan-out prevention: GROUP BY SHIPMENT_ID with COUNT(DISTINCT ORDER_ID).
--   Multiple shipment_lines per shipment are collapsed.
--   The sl→ol join is M:1 (no fan-out at that step).
-- =========================================================================
order_impact AS (
    SELECT
        fsl.SHIPMENT_ID,
        COUNT(DISTINCT fol.ORDER_ID) AS DISTINCT_ORDER_COUNT
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE fsl
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE fol
        ON fsl.ORDER_LINE_ID = fol.ORDER_LINE_ID
    GROUP BY fsl.SHIPMENT_ID
)

-- =========================================================================
-- FINAL ASSEMBLY
-- FACT_SHIPMENT (anchor) + branches + dimensions
-- All joins are 1:1 or M:1 on SHIPMENT_ID grain.
-- DIM_CARRIER: M:1 on CARRIER_ID. DIM_ROUTE: M:1 on ROUTE_ID.
-- =========================================================================
SELECT
    fs.SHIPMENT_ID,
    a.ANALYSIS_AS_OF_DATE,

    fs.SHIPMENT_TYPE,
    fs.SHIPMENT_STATUS,
    fs.CARRIER_ID,
    fs.ROUTE_ID,

    dc.CARRIER_NAME,
    dc.CARRIER_TYPE,
    dc.SERVICE_LEVEL,

    dr.ORIGIN_TYPE,
    dr.ORIGIN_ID,
    dr.DESTINATION_TYPE,
    dr.DESTINATION_ID,
    dr.DISTANCE_KM,
    dr.ROUTE_RISK_LEVEL,

    fs.PLANNED_DEPARTURE_AT,
    fs.ACTUAL_DEPARTURE_AT,
    fs.PLANNED_DELIVERY_AT,
    fs.ACTUAL_DELIVERY_AT,

    fs.SHIPPING_COST,
    fs.IS_ON_TIME,

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

    COALESCE(ea.ROUTE_DEVIATION_EVENT_COUNT, 0) AS ROUTE_DEVIATION_EVENT_COUNT,
    COALESCE(ea.DELAY_REPORTED_EVENT_COUNT, 0)  AS DELAY_REPORTED_EVENT_COUNT,

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
