-- =============================================================================
-- V2.4.0 — Alter MART_SUPPLIER_RISK: Add Severity Metrics
-- =============================================================================
--
-- ## Change purpose
-- Add durable severity-ratio metrics that remain valid after synthetic-data
-- regeneration. Adds LOW_INVENTORY_EXPOSURE_PCT, OUTSTANDING_EXPOSURE_PCT,
-- and their supporting denominator/numerator columns.
-- Removes NEEDS_REORDER_COUNT and BELOW_SAFETY_STOCK_COUNT (replaced by
-- LOW_INVENTORY_POSITION_COUNT with unified OR logic).
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK (full rebuild via CREATE OR REPLACE)
--
-- ## Grain (unchanged)
-- One row per SUPPLIER_ID (75 expected rows)
--
-- ## Column contract
-- 50 columns (was 47 in V2.3.0)
-- +4 new: EXPOSED_INVENTORY_POSITION_COUNT, LOW_INVENTORY_POSITION_COUNT,
--         LOW_INVENTORY_EXPOSURE_PCT, ACTIVE_EXPOSED_OUTSTANDING_VALUE,
--         OUTSTANDING_EXPOSURE_PCT
-- -2 removed: NEEDS_REORDER_COUNT, BELOW_SAFETY_STOCK_COUNT
--
-- ## Preconditions
-- V2.3.0 (MART_SUPPLIER_RISK) must have been applied.
-- Silver baseline tables must exist in SUPPLY_CHAIN_DW.SILVER.
--
-- ## DDL

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK AS

WITH analysis_anchor AS (
    SELECT MAX(LINE_UPDATED_AT)::DATE AS ANALYSIS_AS_OF_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE
),

-- =============================================================================
-- BRANCH 1: Supplier Performance
-- =============================================================================
perf_ranked AS (
    SELECT
        SUPPLIER_ID, MEASUREMENT_DATE_KEY,
        ON_TIME_DELIVERY_PCT, QUALITY_SCORE, AVG_LEAD_TIME_DAYS, FILL_RATE_PCT, RISK_SCORE,
        ROW_NUMBER() OVER (PARTITION BY SUPPLIER_ID ORDER BY MEASUREMENT_DATE_KEY ASC)  AS rn_asc,
        ROW_NUMBER() OVER (PARTITION BY SUPPLIER_ID ORDER BY MEASUREMENT_DATE_KEY DESC) AS rn_desc,
        COUNT(*) OVER (PARTITION BY SUPPLIER_ID) AS period_count
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE
),
supplier_performance AS (
    SELECT
        e.SUPPLIER_ID,
        l.ON_TIME_DELIVERY_PCT AS LATEST_ON_TIME_DELIVERY_PCT,
        e.ON_TIME_DELIVERY_PCT AS EARLIEST_ON_TIME_DELIVERY_PCT,
        l.ON_TIME_DELIVERY_PCT - e.ON_TIME_DELIVERY_PCT AS ON_TIME_DELIVERY_PCT_CHANGE,
        l.QUALITY_SCORE AS LATEST_QUALITY_SCORE,
        e.QUALITY_SCORE AS EARLIEST_QUALITY_SCORE,
        l.QUALITY_SCORE - e.QUALITY_SCORE AS QUALITY_SCORE_CHANGE,
        l.AVG_LEAD_TIME_DAYS AS LATEST_AVG_LEAD_TIME_DAYS,
        e.AVG_LEAD_TIME_DAYS AS EARLIEST_AVG_LEAD_TIME_DAYS,
        l.AVG_LEAD_TIME_DAYS - e.AVG_LEAD_TIME_DAYS AS LEAD_TIME_CHANGE_DAYS,
        l.FILL_RATE_PCT AS LATEST_FILL_RATE_PCT,
        l.RISK_SCORE AS LATEST_RISK_SCORE,
        e.RISK_SCORE AS EARLIEST_RISK_SCORE,
        l.RISK_SCORE - e.RISK_SCORE AS RISK_SCORE_CHANGE,
        e.period_count AS MEASUREMENT_PERIOD_COUNT,
        l.MEASUREMENT_DATE_KEY AS LATEST_MEASUREMENT_DATE
    FROM perf_ranked e
    JOIN perf_ranked l ON e.SUPPLIER_ID = l.SUPPLIER_ID AND l.rn_desc = 1
    WHERE e.rn_asc = 1
),

-- =============================================================================
-- BRANCH 2: Supplier Dependency
-- =============================================================================
active_bridge AS (
    SELECT SUPPLIER_ID, PART_ID, PREFERRED_SUPPLIER_FLAG
    FROM SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART
    WHERE ACTIVE_FLAG = TRUE
),
supplier_dependency AS (
    SELECT
        SUPPLIER_ID,
        COUNT(DISTINCT PART_ID) AS SUPPLIED_PART_COUNT,
        SUM(CASE WHEN PREFERRED_SUPPLIER_FLAG = TRUE THEN 1 ELSE 0 END) AS PREFERRED_PART_COUNT
    FROM active_bridge
    GROUP BY SUPPLIER_ID
),

-- =============================================================================
-- BRANCH 3: Inventory Exposure (revised for V2.4.0)
-- =============================================================================
inventory_exposure AS (
    SELECT
        ab.SUPPLIER_ID,
        COUNT(DISTINCT inv.PLANT_ID)                                               AS EXPOSED_PLANT_COUNT,
        COUNT(DISTINCT inv.PART_ID)                                                AS INVENTORY_PART_COUNT,
        SUM(inv.AVAILABLE_QTY)                                                     AS EXPOSED_INVENTORY_QTY,
        COUNT(DISTINCT inv.PLANT_ID, inv.PART_ID)                                  AS EXPOSED_INVENTORY_POSITION_COUNT,
        SUM(CASE WHEN inv.NEEDS_REORDER OR inv.BELOW_SAFETY_STOCK THEN 1 ELSE 0 END)
                                                                                   AS LOW_INVENTORY_POSITION_COUNT
    FROM active_bridge ab
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT inv ON ab.PART_ID = inv.PART_ID
    GROUP BY ab.SUPPLIER_ID
),

-- =============================================================================
-- BRANCH 4: Order Exposure (revised for V2.4.0)
-- =============================================================================
shipped_per_line AS (
    SELECT ORDER_LINE_ID, SUM(SHIPPED_QTY) AS shipped_qty
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE
    GROUP BY ORDER_LINE_ID
),
order_line_enriched AS (
    SELECT
        ol.ORDER_LINE_ID, ol.ORDER_ID, ol.PART_ID, ol.LINE_STATUS,
        ol.ORDERED_QTY, ol.UNIT_PRICE, ol.LINE_AMOUNT, ol.REQUESTED_DELIVERY_DATE_KEY,
        COALESCE(sp.shipped_qty, 0) AS shipped_qty,
        GREATEST(0, ol.ORDERED_QTY - COALESCE(sp.shipped_qty, 0)) AS outstanding_qty,
        a.ANALYSIS_AS_OF_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE ol
    CROSS JOIN analysis_anchor a
    LEFT JOIN shipped_per_line sp ON ol.ORDER_LINE_ID = sp.ORDER_LINE_ID
),
order_exposure AS (
    SELECT
        ab.SUPPLIER_ID,
        COUNT(DISTINCT CASE WHEN ole.LINE_STATUS != 'CANCELLED' THEN ole.ORDER_ID END)
            AS EXPOSED_ORDER_COUNT,
        COUNT(DISTINCT CASE WHEN ole.LINE_STATUS != 'CANCELLED' THEN ole.ORDER_LINE_ID END)
            AS EXPOSED_ORDER_LINE_COUNT,
        SUM(CASE WHEN ole.LINE_STATUS != 'CANCELLED' THEN ole.ORDERED_QTY ELSE 0 END)
            AS EXPOSED_ORDERED_QTY,
        SUM(CASE WHEN ole.LINE_STATUS NOT IN ('DELIVERED','CANCELLED') THEN ole.LINE_AMOUNT ELSE 0 END)
            AS ACTIVE_EXPOSED_ORDER_VALUE,
        SUM(CASE WHEN ole.LINE_STATUS != 'CANCELLED' THEN ole.outstanding_qty ELSE 0 END)
            AS EXPOSED_OUTSTANDING_QTY,
        SUM(CASE WHEN ole.LINE_STATUS != 'CANCELLED' THEN ole.outstanding_qty * ole.UNIT_PRICE ELSE 0 END)
            AS EXPOSED_OUTSTANDING_VALUE,
        SUM(CASE WHEN ole.LINE_STATUS NOT IN ('DELIVERED','CANCELLED') THEN ole.outstanding_qty * ole.UNIT_PRICE ELSE 0 END)
            AS ACTIVE_EXPOSED_OUTSTANDING_VALUE,
        COUNT(DISTINCT CASE
            WHEN ole.LINE_STATUS NOT IN ('DELIVERED','CANCELLED')
                 AND ole.REQUESTED_DELIVERY_DATE_KEY < ole.ANALYSIS_AS_OF_DATE
                 AND ole.shipped_qty < ole.ORDERED_QTY
            THEN ole.ORDER_LINE_ID END)
            AS EXPOSED_LATE_ORDER_LINE_COUNT
    FROM order_line_enriched ole
    JOIN active_bridge ab ON ole.PART_ID = ab.PART_ID
    GROUP BY ab.SUPPLIER_ID
),

-- =============================================================================
-- BRANCH 5: Shipment Exposure (unchanged from V2.3.0)
-- =============================================================================
supplier_shipment_pairs AS (
    SELECT DISTINCT
        ab.SUPPLIER_ID, s.SHIPMENT_ID, s.IS_ON_TIME
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE sl
    JOIN active_bridge ab ON sl.PART_ID = ab.PART_ID
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT s ON sl.SHIPMENT_ID = s.SHIPMENT_ID
),
shipment_exposure AS (
    SELECT
        SUPPLIER_ID,
        COUNT(DISTINCT SHIPMENT_ID) AS EXPOSED_SHIPMENT_COUNT,
        COUNT(DISTINCT CASE WHEN IS_ON_TIME = FALSE THEN SHIPMENT_ID END) AS LATE_SHIPMENT_COUNT
    FROM supplier_shipment_pairs
    GROUP BY SUPPLIER_ID
)

-- =============================================================================
-- FINAL: Join all branches to DIM_SUPPLIER (all 1:1 on SUPPLIER_ID)
-- =============================================================================
SELECT
    -- 1. Metadata
    a.ANALYSIS_AS_OF_DATE,

    -- 2. Supplier attributes
    ds.SUPPLIER_ID,
    ds.SUPPLIER_NAME,
    ds.SUPPLIER_TIER,
    ds.SUPPLIER_STATUS,

    -- 3. Supplier performance (15 columns)
    sp.LATEST_ON_TIME_DELIVERY_PCT,
    sp.EARLIEST_ON_TIME_DELIVERY_PCT,
    sp.ON_TIME_DELIVERY_PCT_CHANGE,
    sp.LATEST_QUALITY_SCORE,
    sp.EARLIEST_QUALITY_SCORE,
    sp.QUALITY_SCORE_CHANGE,
    sp.LATEST_AVG_LEAD_TIME_DAYS,
    sp.EARLIEST_AVG_LEAD_TIME_DAYS,
    sp.LEAD_TIME_CHANGE_DAYS,
    sp.LATEST_FILL_RATE_PCT,
    sp.LATEST_RISK_SCORE,
    sp.EARLIEST_RISK_SCORE,
    sp.RISK_SCORE_CHANGE,
    sp.MEASUREMENT_PERIOD_COUNT,
    sp.LATEST_MEASUREMENT_DATE,

    -- 4. Dependency exposure (2 columns)
    sd.SUPPLIED_PART_COUNT,
    sd.PREFERRED_PART_COUNT,

    -- 5. Inventory exposure (6 columns — revised)
    COALESCE(ie.EXPOSED_PLANT_COUNT, 0)                AS EXPOSED_PLANT_COUNT,
    COALESCE(ie.INVENTORY_PART_COUNT, 0)               AS INVENTORY_PART_COUNT,
    COALESCE(ie.EXPOSED_INVENTORY_QTY, 0)              AS EXPOSED_INVENTORY_QTY,
    COALESCE(ie.EXPOSED_INVENTORY_POSITION_COUNT, 0)   AS EXPOSED_INVENTORY_POSITION_COUNT,
    COALESCE(ie.LOW_INVENTORY_POSITION_COUNT, 0)       AS LOW_INVENTORY_POSITION_COUNT,
    ROUND(100.0 * COALESCE(ie.LOW_INVENTORY_POSITION_COUNT, 0)
          / NULLIF(COALESCE(ie.EXPOSED_INVENTORY_POSITION_COUNT, 0), 0), 2)
        AS LOW_INVENTORY_EXPOSURE_PCT,

    -- 6. Order exposure (9 columns — revised)
    COALESCE(oe.EXPOSED_ORDER_COUNT, 0)                    AS EXPOSED_ORDER_COUNT,
    COALESCE(oe.EXPOSED_ORDER_LINE_COUNT, 0)               AS EXPOSED_ORDER_LINE_COUNT,
    COALESCE(oe.EXPOSED_ORDERED_QTY, 0)                    AS EXPOSED_ORDERED_QTY,
    COALESCE(oe.ACTIVE_EXPOSED_ORDER_VALUE, 0)             AS ACTIVE_EXPOSED_ORDER_VALUE,
    COALESCE(oe.EXPOSED_OUTSTANDING_QTY, 0)                AS EXPOSED_OUTSTANDING_QTY,
    COALESCE(oe.EXPOSED_OUTSTANDING_VALUE, 0)              AS EXPOSED_OUTSTANDING_VALUE,
    COALESCE(oe.ACTIVE_EXPOSED_OUTSTANDING_VALUE, 0)       AS ACTIVE_EXPOSED_OUTSTANDING_VALUE,
    ROUND(100.0 * COALESCE(oe.ACTIVE_EXPOSED_OUTSTANDING_VALUE, 0)
          / NULLIF(COALESCE(oe.ACTIVE_EXPOSED_ORDER_VALUE, 0), 0), 2)
        AS OUTSTANDING_EXPOSURE_PCT,
    COALESCE(oe.EXPOSED_LATE_ORDER_LINE_COUNT, 0)          AS EXPOSED_LATE_ORDER_LINE_COUNT,

    -- 7. Shipment exposure (3 columns — unchanged)
    COALESCE(se.EXPOSED_SHIPMENT_COUNT, 0)     AS EXPOSED_SHIPMENT_COUNT,
    COALESCE(se.LATE_SHIPMENT_COUNT, 0)        AS LATE_SHIPMENT_COUNT,
    ROUND(100.0 * COALESCE(se.LATE_SHIPMENT_COUNT, 0)
          / NULLIF(COALESCE(se.EXPOSED_SHIPMENT_COUNT, 0), 0), 2)
        AS LATE_SHIPMENT_PCT,

    -- 8. Explainability flags (10 columns)
    (sp.ON_TIME_DELIVERY_PCT_CHANGE < 0)       AS HAS_OTD_DETERIORATION,
    (sp.QUALITY_SCORE_CHANGE < 0)              AS HAS_QUALITY_DETERIORATION,
    (sp.LEAD_TIME_CHANGE_DAYS > 0)             AS HAS_LEAD_TIME_DETERIORATION,
    (sp.RISK_SCORE_CHANGE > 0)                 AS HAS_RISK_SCORE_INCREASE,

    (sp.ON_TIME_DELIVERY_PCT_CHANGE < 0
     OR sp.QUALITY_SCORE_CHANGE < 0
     OR sp.LEAD_TIME_CHANGE_DAYS > 0)          AS HAS_SUPPLIER_PERFORMANCE_DETERIORATION,

    (COALESCE(se.LATE_SHIPMENT_COUNT, 0) > 0)  AS HAS_LATE_SHIPMENT_EXPOSURE,

    (COALESCE(oe.EXPOSED_OUTSTANDING_VALUE, 0) > 0)
                                               AS HAS_OUTSTANDING_ORDER_EXPOSURE,

    (COALESCE(ie.LOW_INVENTORY_POSITION_COUNT, 0) > 0)
                                               AS HAS_LOW_INVENTORY_EXPOSURE,

    (COALESCE(se.LATE_SHIPMENT_COUNT, 0) > 0
     OR COALESCE(oe.EXPOSED_OUTSTANDING_VALUE, 0) > 0
     OR COALESCE(ie.LOW_INVENTORY_POSITION_COUNT, 0) > 0)
                                               AS HAS_DOWNSTREAM_EXPOSURE,

    ((sp.ON_TIME_DELIVERY_PCT_CHANGE < 0
      OR sp.QUALITY_SCORE_CHANGE < 0
      OR sp.LEAD_TIME_CHANGE_DAYS > 0)
     AND
     (COALESCE(se.LATE_SHIPMENT_COUNT, 0) > 0
      OR COALESCE(oe.EXPOSED_OUTSTANDING_VALUE, 0) > 0
      OR COALESCE(ie.LOW_INVENTORY_POSITION_COUNT, 0) > 0))
                                               AS IS_SUPPLIER_AT_RISK

FROM SUPPLY_CHAIN_DW.SILVER.DIM_SUPPLIER ds
CROSS JOIN analysis_anchor a
JOIN supplier_performance sp ON ds.SUPPLIER_ID = sp.SUPPLIER_ID
JOIN supplier_dependency sd  ON ds.SUPPLIER_ID = sd.SUPPLIER_ID
LEFT JOIN inventory_exposure ie ON ds.SUPPLIER_ID = ie.SUPPLIER_ID
LEFT JOIN order_exposure oe     ON ds.SUPPLIER_ID = oe.SUPPLIER_ID
LEFT JOIN shipment_exposure se  ON ds.SUPPLIER_ID = se.SUPPLIER_ID;

-- ## Post-change validation
-- Column count: 50
-- OUTSTANDING_EXPOSURE_PCT BETWEEN 0 AND 100 for all rows
-- LOW_INVENTORY_EXPOSURE_PCT BETWEEN 0 AND 100 for all rows
-- LOW_INVENTORY_POSITION_COUNT <= EXPOSED_INVENTORY_POSITION_COUNT
-- ACTIVE_EXPOSED_OUTSTANDING_VALUE <= ACTIVE_EXPOSED_ORDER_VALUE
-- All flag consistency checks from V2.3.0

-- ## Rollback / manual recovery
-- Re-run V2.3.0 migration to restore previous version:
-- See migrations/V2.3.0__create_mart_supplier_risk.sql
