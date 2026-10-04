-- =============================================================================
-- Populate MART_INVENTORY_RISK
-- =============================================================================
-- Populates SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK from Silver sources.
-- 27 columns (24 original + 3 demand coverage from V3.7.0).
--
-- Three pre-aggregation branches plus dimension enrichment on
-- FACT_INVENTORY_SNAPSHOT base:
--   Branch 1: Active supplier count per PART_ID
--   Branch 2: Current demand exposure per PLANT_ID + PART_ID
--   Branch 3: 90-day order demand per PLANT_ID + PART_ID (for days of coverage)
--
-- Prerequisites: V3.2.0 + V3.7.0 (table with all 27 columns).
-- Idempotent: TRUNCATE + INSERT pattern.
-- =============================================================================

TRUNCATE TABLE SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

INSERT INTO SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK (
    PLANT_ID, PART_ID, ANALYSIS_AS_OF_DATE,
    PLANT_NAME, PART_NAME, PART_CATEGORY, CRITICALITY,
    ON_HAND_QTY, RESERVED_QTY, AVAILABLE_QTY, SAFETY_STOCK, REORDER_POINT,
    INVENTORY_STATUS, SNAPSHOT_DATE_KEY,
    BELOW_SAFETY_STOCK_QTY, SHORTAGE_QTY, NEEDS_REORDER, BELOW_SAFETY_STOCK, IS_OUT_OF_STOCK,
    ACTIVE_SUPPLIER_COUNT,
    ACTIVE_ORDER_COUNT, ACTIVE_ORDERED_QTY, OUTSTANDING_ORDER_QTY, OUTSTANDING_ORDER_VALUE,
    ORDER_DEMAND_QTY_90D, AVG_DAILY_ORDER_DEMAND_90D, DAYS_OF_DEMAND_COVERAGE_90D
)
WITH analysis_anchor AS (
    SELECT MAX(LAST_UPDATED_AT)::DATE AS ANALYSIS_AS_OF_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT
),

-- =========================================================================
-- BRANCH 1: Active Supplier Count per PART_ID
-- Source: BRIDGE_SUPPLIER_PART (active only)
-- Fan-out prevention: GROUP BY PART_ID collapses to 1 row per part.
-- =========================================================================
supplier_count AS (
    SELECT
        PART_ID,
        COUNT(DISTINCT SUPPLIER_ID) AS ACTIVE_SUPPLIER_COUNT
    FROM SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART
    WHERE ACTIVE_FLAG = TRUE
    GROUP BY PART_ID
),

-- =========================================================================
-- BRANCH 2: Current Demand Exposure per PLANT_ID + PART_ID
-- Step 2a: shipped qty per ORDER_LINE_ID (pre-aggregate FACT_SHIPMENT_LINE)
-- Step 2b: non-cancelled lines with outstanding > 0, grouped to PLANT_ID+PART_ID
-- Fan-out prevention:
--   shipped_per_line: SUM GROUP BY ORDER_LINE_ID → 1 row per line
--   demand_exposure: GROUP BY PLANT_ID, PART_ID → matches mart grain exactly
-- =========================================================================
shipped_per_line AS (
    SELECT
        ORDER_LINE_ID,
        SUM(SHIPPED_QTY) AS LINE_SHIPPED_QTY
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE
    GROUP BY ORDER_LINE_ID
),
demand_exposure AS (
    SELECT
        fol.PLANT_ID,
        fol.PART_ID,
        COUNT(DISTINCT fol.ORDER_ID)   AS ACTIVE_ORDER_COUNT,
        SUM(fol.ORDERED_QTY)           AS ACTIVE_ORDERED_QTY,
        SUM(GREATEST(fol.ORDERED_QTY - COALESCE(sp.LINE_SHIPPED_QTY, 0), 0))
            AS OUTSTANDING_ORDER_QTY,
        SUM(GREATEST(fol.ORDERED_QTY - COALESCE(sp.LINE_SHIPPED_QTY, 0), 0) * fol.UNIT_PRICE)
            AS OUTSTANDING_ORDER_VALUE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE fol
    LEFT JOIN shipped_per_line sp ON fol.ORDER_LINE_ID = sp.ORDER_LINE_ID
    WHERE fol.LINE_STATUS != 'CANCELLED'
      AND GREATEST(fol.ORDERED_QTY - COALESCE(sp.LINE_SHIPPED_QTY, 0), 0) > 0
    GROUP BY fol.PLANT_ID, fol.PART_ID
),

-- =========================================================================
-- BRANCH 3: 90-Day Order Demand per PLANT_ID + PART_ID
-- Source: FACT_ORDER_LINE (non-cancelled, trailing 90 days from max order date)
-- Used for: Days of Demand Coverage (90D)
-- This is order demand, NOT physical consumption.
-- Fan-out prevention: GROUP BY PLANT_ID, PART_ID → matches mart grain exactly
-- =========================================================================
order_date_anchor AS (
    SELECT MAX(ORDER_DATE_KEY) AS max_order_date
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE
),
demand_90d AS (
    SELECT
        fol.PLANT_ID,
        fol.PART_ID,
        SUM(fol.ORDERED_QTY) AS ORDER_DEMAND_QTY_90D
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE fol
    CROSS JOIN order_date_anchor oda
    WHERE fol.ORDER_DATE_KEY >= DATEADD(DAY, -90, oda.max_order_date)
      AND fol.LINE_STATUS != 'CANCELLED'
    GROUP BY fol.PLANT_ID, fol.PART_ID
)

-- =========================================================================
-- FINAL ASSEMBLY
-- FACT_INVENTORY_SNAPSHOT (anchor) + branches + dimensions
-- All joins are 1:1 or M:1 on PLANT_ID + PART_ID grain.
-- =========================================================================
SELECT
    inv.PLANT_ID,
    inv.PART_ID,
    a.ANALYSIS_AS_OF_DATE,

    dp.PLANT_NAME,

    dpt.PART_NAME,
    dpt.PART_CATEGORY,
    dpt.CRITICALITY,

    inv.ON_HAND_QTY,
    inv.RESERVED_QTY,
    inv.AVAILABLE_QTY,
    inv.SAFETY_STOCK,
    inv.REORDER_POINT,
    inv.INVENTORY_STATUS,
    inv.SNAPSHOT_DATE_KEY,

    GREATEST(inv.SAFETY_STOCK - inv.AVAILABLE_QTY, 0)  AS BELOW_SAFETY_STOCK_QTY,
    GREATEST(inv.REORDER_POINT - inv.AVAILABLE_QTY, 0)  AS SHORTAGE_QTY,
    inv.NEEDS_REORDER,
    inv.BELOW_SAFETY_STOCK,
    (inv.AVAILABLE_QTY = 0)                              AS IS_OUT_OF_STOCK,

    COALESCE(sc.ACTIVE_SUPPLIER_COUNT, 0)   AS ACTIVE_SUPPLIER_COUNT,

    COALESCE(de.ACTIVE_ORDER_COUNT, 0)      AS ACTIVE_ORDER_COUNT,
    COALESCE(de.ACTIVE_ORDERED_QTY, 0)      AS ACTIVE_ORDERED_QTY,
    COALESCE(de.OUTSTANDING_ORDER_QTY, 0)   AS OUTSTANDING_ORDER_QTY,
    COALESCE(de.OUTSTANDING_ORDER_VALUE, 0) AS OUTSTANDING_ORDER_VALUE,

    -- Branch 3: Days of Demand Coverage (90D)
    -- ORDER_DEMAND_QTY_90D: NULL if no demand in 90-day window (COALESCE not applied)
    d90.ORDER_DEMAND_QTY_90D,
    ROUND(d90.ORDER_DEMAND_QTY_90D / 90.0, 4)  AS AVG_DAILY_ORDER_DEMAND_90D,
    CASE
        WHEN d90.ORDER_DEMAND_QTY_90D > 0
        THEN ROUND(inv.AVAILABLE_QTY / (d90.ORDER_DEMAND_QTY_90D / 90.0), 4)
        ELSE NULL
    END                                         AS DAYS_OF_DEMAND_COVERAGE_90D

FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT inv
CROSS JOIN analysis_anchor a
LEFT JOIN supplier_count sc
    ON inv.PART_ID = sc.PART_ID
LEFT JOIN demand_exposure de
    ON inv.PLANT_ID = de.PLANT_ID AND inv.PART_ID = de.PART_ID
LEFT JOIN demand_90d d90
    ON inv.PLANT_ID = d90.PLANT_ID AND inv.PART_ID = d90.PART_ID
LEFT JOIN SUPPLY_CHAIN_DW.SILVER.DIM_PLANT dp
    ON inv.PLANT_ID = dp.PLANT_ID
LEFT JOIN SUPPLY_CHAIN_DW.SILVER.DIM_PART dpt
    ON inv.PART_ID = dpt.PART_ID;
