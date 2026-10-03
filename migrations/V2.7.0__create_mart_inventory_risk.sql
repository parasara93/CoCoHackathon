-- =============================================================================
-- V2.7.0 — Create MART_INVENTORY_RISK
-- =============================================================================
--
-- ## Change purpose
-- Fifth Gold analytical mart: inventory-position risk and demand exposure.
-- Identifies plant/part positions below safety stock or reorder thresholds,
-- quantifies current outstanding order demand, and provides supplier context.
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
--
-- ## Grain
-- One row per PLANT_ID + PART_ID (2,250 expected rows)
--
-- ## Design reference
-- 24-column contract. Two pre-aggregation branches (supplier count, demand
-- exposure) plus dimension enrichment on a FACT_INVENTORY_SNAPSHOT base.
--
-- ## Preconditions
-- V2.0.0 (GOLD schema) must be applied.
-- Silver baseline tables must exist in SUPPLY_CHAIN_DW.SILVER.
--
-- ## DDL

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK AS

WITH analysis_anchor AS (
    -- Deterministic analysis date from FACT_INVENTORY_SNAPSHOT.
    SELECT MAX(LAST_UPDATED_AT)::DATE AS ANALYSIS_AS_OF_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT
),

-- =============================================================================
-- BRANCH 1: Active Supplier Count → PART_ID
-- Source: BRIDGE_SUPPLIER_PART (active only)
-- Target grain: PART_ID (689 rows — parts with active suppliers)
-- =============================================================================
supplier_count AS (
    SELECT
        PART_ID,
        COUNT(DISTINCT SUPPLIER_ID) AS ACTIVE_SUPPLIER_COUNT
    FROM SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART
    WHERE ACTIVE_FLAG = TRUE
    GROUP BY PART_ID
),

-- =============================================================================
-- BRANCH 2: Current Demand Exposure → PLANT_ID + PART_ID
-- Step 2a: Aggregate shipped qty to ORDER_LINE_ID (line-safe pattern).
-- Step 2b: Include only non-cancelled lines with outstanding qty > 0.
--          Do NOT exclude lines based on LINE_STATUS = 'DELIVERED'.
-- Target grain: PLANT_ID + PART_ID
-- =============================================================================
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
)

-- =============================================================================
-- FINAL ASSEMBLY
-- FACT_INVENTORY_SNAPSHOT (2,250 rows) + Branch 1 + Branch 2 + dimensions.
-- All joins are 1:1 or M:1 on PLANT_ID + PART_ID grain.
-- =============================================================================
SELECT
    -- 1. Identity / Context
    inv.PLANT_ID,
    inv.PART_ID,
    a.ANALYSIS_AS_OF_DATE,

    -- 2. Plant Attributes
    dp.PLANT_NAME,

    -- 3. Part Attributes
    dpt.PART_NAME,
    dpt.PART_CATEGORY,
    dpt.CRITICALITY,

    -- 4. Inventory Facts (pass-through from Silver)
    inv.ON_HAND_QTY,
    inv.RESERVED_QTY,
    inv.AVAILABLE_QTY,
    inv.SAFETY_STOCK,
    inv.REORDER_POINT,
    inv.INVENTORY_STATUS,
    inv.SNAPSHOT_DATE_KEY,

    -- 5. Risk Derivations
    GREATEST(inv.SAFETY_STOCK - inv.AVAILABLE_QTY, 0)
        AS BELOW_SAFETY_STOCK_QTY,
    GREATEST(inv.REORDER_POINT - inv.AVAILABLE_QTY, 0)
        AS SHORTAGE_QTY,
    inv.NEEDS_REORDER,
    inv.BELOW_SAFETY_STOCK,
    (inv.AVAILABLE_QTY = 0)
        AS IS_OUT_OF_STOCK,

    -- 6. Supplier Context
    COALESCE(sc.ACTIVE_SUPPLIER_COUNT, 0)   AS ACTIVE_SUPPLIER_COUNT,

    -- 7. Demand Exposure
    COALESCE(de.ACTIVE_ORDER_COUNT, 0)      AS ACTIVE_ORDER_COUNT,
    COALESCE(de.ACTIVE_ORDERED_QTY, 0)      AS ACTIVE_ORDERED_QTY,
    COALESCE(de.OUTSTANDING_ORDER_QTY, 0)   AS OUTSTANDING_ORDER_QTY,
    COALESCE(de.OUTSTANDING_ORDER_VALUE, 0) AS OUTSTANDING_ORDER_VALUE

FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT inv
CROSS JOIN analysis_anchor a
LEFT JOIN supplier_count sc
    ON inv.PART_ID = sc.PART_ID
LEFT JOIN demand_exposure de
    ON inv.PLANT_ID = de.PLANT_ID AND inv.PART_ID = de.PART_ID
LEFT JOIN SUPPLY_CHAIN_DW.SILVER.DIM_PLANT dp
    ON inv.PLANT_ID = dp.PLANT_ID
LEFT JOIN SUPPLY_CHAIN_DW.SILVER.DIM_PART dpt
    ON inv.PART_ID = dpt.PART_ID;

-- ## Post-change validation
-- Run validations/gold/mart_inventory_risk_checks.sql
-- Run validations/gold/mart_inventory_risk_scenario_structural.sql
-- Run validations/gold/mart_inventory_risk_scenario_behavioral.sql

-- ## Rollback / manual recovery
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;
