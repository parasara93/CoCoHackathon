-- =============================================================================
-- V2.5.0 — Create MART_ORDER_FULFILLMENT
-- =============================================================================
--
-- ## Change purpose
-- Third Gold analytical mart: order-level fulfillment performance.
-- Classifies every order as FULFILLED, PARTIALLY_FULFILLED, UNFULFILLED,
-- or CANCELLED using line-safe shipped-quantity capping.
-- Derives current and delivered lateness at order-line grain before
-- aggregating to ORDER_ID.
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT
--
-- ## Grain
-- One row per ORDER_ID (50,000 expected rows)
--
-- ## Design reference
-- 37-column v3 contract. Two-branch aggregate-before-join architecture.
-- Branch 1: line fulfillment + lateness → ORDER_ID.
-- Branch 2: shipment metrics → ORDER_ID.
-- Final: LEFT JOIN branches + DIM_CUSTOMER + DIM_PLANT.
--
-- ## Preconditions
-- V2.0.0 (GOLD schema) must be applied.
-- Silver baseline tables must exist in SUPPLY_CHAIN_DW.SILVER.
--
-- ## DDL

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT AS

WITH analysis_anchor AS (
    -- Deterministic analysis date: consistent across all Gold marts.
    SELECT MAX(LINE_UPDATED_AT)::DATE AS ANALYSIS_AS_OF_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE
),

-- =============================================================================
-- BRANCH 1: Line-Level Fulfillment and Lateness → ORDER_ID
-- =============================================================================

-- Step 1a: Aggregate shipment lines to ORDER_LINE_ID.
-- Source grain: SHIPMENT_LINE_ID (180,115 rows)
-- Target grain: ORDER_LINE_ID (104,740 rows — order lines with shipments)
shipment_per_line AS (
    SELECT
        fsl.ORDER_LINE_ID,
        SUM(fsl.SHIPPED_QTY)            AS LINE_SHIPPED_QTY,
        MAX(fs.ACTUAL_DELIVERY_AT)::DATE AS LINE_MAX_ACTUAL_DELIVERY_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE fsl
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT fs
        ON fsl.SHIPMENT_ID = fs.SHIPMENT_ID
    GROUP BY fsl.ORDER_LINE_ID
),

-- Step 1b: Enrich every order line with line-safe fulfillment and lateness.
-- Source grain: ORDER_LINE_ID (149,756 rows)
-- Left join preserves 45,016 lines with no shipments.
line_enriched AS (
    SELECT
        fol.ORDER_LINE_ID,
        fol.ORDER_ID,
        fol.CUSTOMER_ID,
        fol.PLANT_ID,
        fol.ORDER_DATE_KEY,
        fol.REQUESTED_DELIVERY_DATE_KEY,
        fol.LINE_STATUS,
        fol.ORDERED_QTY,
        fol.UNIT_PRICE,
        fol.LINE_AMOUNT,
        a.ANALYSIS_AS_OF_DATE,

        -- Raw shipped qty (NULL when no shipment lines)
        spl.LINE_SHIPPED_QTY,

        -- Line-safe fulfillment metrics (non-cancelled only; cancelled excluded at agg)
        LEAST(COALESCE(spl.LINE_SHIPPED_QTY, 0), fol.ORDERED_QTY)
            AS LINE_EFFECTIVE_SHIPPED_QTY,
        GREATEST(fol.ORDERED_QTY - COALESCE(spl.LINE_SHIPPED_QTY, 0), 0)
            AS LINE_OUTSTANDING_QTY,
        GREATEST(COALESCE(spl.LINE_SHIPPED_QTY, 0) - fol.ORDERED_QTY, 0)
            AS LINE_OVER_SHIPPED_QTY,

        -- Delivery timestamp
        spl.LINE_MAX_ACTUAL_DELIVERY_DATE,

        -- Current lateness (line grain)
        CASE
            WHEN fol.LINE_STATUS != 'CANCELLED'
                 AND GREATEST(fol.ORDERED_QTY - COALESCE(spl.LINE_SHIPPED_QTY, 0), 0) > 0
                 AND fol.REQUESTED_DELIVERY_DATE_KEY < a.ANALYSIS_AS_OF_DATE
            THEN TRUE ELSE FALSE
        END AS LINE_IS_CURRENT_LATE,

        CASE
            WHEN fol.LINE_STATUS != 'CANCELLED'
                 AND GREATEST(fol.ORDERED_QTY - COALESCE(spl.LINE_SHIPPED_QTY, 0), 0) > 0
                 AND fol.REQUESTED_DELIVERY_DATE_KEY < a.ANALYSIS_AS_OF_DATE
            THEN DATEDIFF('DAY', fol.REQUESTED_DELIVERY_DATE_KEY, a.ANALYSIS_AS_OF_DATE)
        END AS LINE_CURRENT_DELAY_DAYS,

        -- Delivered lateness (line grain)
        CASE
            WHEN fol.LINE_STATUS != 'CANCELLED'
                 AND spl.LINE_MAX_ACTUAL_DELIVERY_DATE IS NOT NULL
                 AND spl.LINE_MAX_ACTUAL_DELIVERY_DATE > fol.REQUESTED_DELIVERY_DATE_KEY
            THEN TRUE ELSE FALSE
        END AS LINE_IS_DELIVERED_LATE,

        CASE
            WHEN fol.LINE_STATUS != 'CANCELLED'
                 AND spl.LINE_MAX_ACTUAL_DELIVERY_DATE IS NOT NULL
                 AND spl.LINE_MAX_ACTUAL_DELIVERY_DATE > fol.REQUESTED_DELIVERY_DATE_KEY
            THEN DATEDIFF('DAY', fol.REQUESTED_DELIVERY_DATE_KEY, spl.LINE_MAX_ACTUAL_DELIVERY_DATE)
        END AS LINE_DELIVERED_DELAY_DAYS

    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE fol
    CROSS JOIN analysis_anchor a
    LEFT JOIN shipment_per_line spl
        ON fol.ORDER_LINE_ID = spl.ORDER_LINE_ID
),

-- Step 1c: Aggregate line-enriched data to ORDER_ID.
-- Source grain: ORDER_LINE_ID (149,756 rows)
-- Target grain: ORDER_ID (50,000 rows)
order_fulfillment AS (
    SELECT
        ORDER_ID,
        MAX(ANALYSIS_AS_OF_DATE)             AS ANALYSIS_AS_OF_DATE,

        -- Order attributes (deterministic per order — verified 1:1)
        ANY_VALUE(CUSTOMER_ID)               AS CUSTOMER_ID,
        ANY_VALUE(PLANT_ID)                  AS PLANT_ID,
        MIN(ORDER_DATE_KEY)                  AS ORDER_DATE,

        -- Requested delivery date: descriptive only, NOT a lateness driver
        MAX(CASE WHEN LINE_STATUS != 'CANCELLED' THEN REQUESTED_DELIVERY_DATE_KEY END)
            AS REQUESTED_DELIVERY_DATE,

        -- Line counts
        COUNT(*)                             AS TOTAL_ORDER_LINE_COUNT,
        SUM(CASE WHEN LINE_STATUS = 'CANCELLED' THEN 1 ELSE 0 END)
            AS CANCELLED_LINE_COUNT,

        -- Quantity metrics (non-cancelled lines only)
        SUM(ORDERED_QTY)                     AS ORDERED_QTY,
        SUM(CASE WHEN LINE_STATUS != 'CANCELLED' THEN ORDERED_QTY ELSE 0 END)
            AS ACTIVE_ORDERED_QTY,
        SUM(CASE WHEN LINE_STATUS != 'CANCELLED' THEN COALESCE(LINE_SHIPPED_QTY, 0) ELSE 0 END)
            AS RAW_SHIPPED_QTY,
        SUM(CASE WHEN LINE_STATUS != 'CANCELLED' THEN LINE_EFFECTIVE_SHIPPED_QTY ELSE 0 END)
            AS EFFECTIVE_SHIPPED_QTY,
        SUM(CASE WHEN LINE_STATUS != 'CANCELLED' THEN LINE_OUTSTANDING_QTY ELSE 0 END)
            AS OUTSTANDING_QTY,
        SUM(CASE WHEN LINE_STATUS != 'CANCELLED' THEN LINE_OVER_SHIPPED_QTY ELSE 0 END)
            AS OVER_SHIPPED_QTY,

        -- Value metrics
        SUM(LINE_AMOUNT)                     AS ORDER_VALUE,
        SUM(CASE WHEN LINE_STATUS != 'CANCELLED' THEN LINE_AMOUNT ELSE 0 END)
            AS ACTIVE_ORDER_VALUE,
        SUM(CASE WHEN LINE_STATUS != 'CANCELLED' THEN LINE_OUTSTANDING_QTY * UNIT_PRICE ELSE 0 END)
            AS OUTSTANDING_VALUE,

        -- Lateness: current (aggregated from line grain)
        MAX(LINE_IS_CURRENT_LATE::INT) = 1   AS IS_CURRENT_LATE,
        MAX(CASE WHEN LINE_IS_CURRENT_LATE THEN LINE_CURRENT_DELAY_DAYS END)
            AS CURRENT_DELAY_DAYS,

        -- Lateness: delivered (aggregated from line grain)
        MAX(LINE_IS_DELIVERED_LATE::INT) = 1 AS IS_DELIVERED_LATE,
        MAX(CASE WHEN LINE_IS_DELIVERED_LATE THEN LINE_DELIVERED_DELAY_DAYS END)
            AS MAX_DELIVERED_DELAY_DAYS,

        -- Last actual delivery across all non-cancelled lines
        MAX(CASE WHEN LINE_STATUS != 'CANCELLED' THEN LINE_MAX_ACTUAL_DELIVERY_DATE END)
            AS LAST_ACTUAL_DELIVERY_DATE

    FROM line_enriched
    GROUP BY ORDER_ID
),

-- =============================================================================
-- BRANCH 2: Shipment Metrics → ORDER_ID
-- =============================================================================

-- Step 2a: Derive distinct (ORDER_ID, SHIPMENT_ID) pairs.
-- Source: FACT_SHIPMENT_LINE → FACT_ORDER_LINE (for ORDER_ID)
-- Then join FACT_SHIPMENT for IS_ON_TIME.
order_shipment_pairs AS (
    SELECT DISTINCT
        fol.ORDER_ID,
        fsl.SHIPMENT_ID,
        fs.IS_ON_TIME
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE fsl
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE fol
        ON fsl.ORDER_LINE_ID = fol.ORDER_LINE_ID
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT fs
        ON fsl.SHIPMENT_ID = fs.SHIPMENT_ID
    WHERE fol.LINE_STATUS != 'CANCELLED'
),

-- Step 2b: Aggregate to ORDER_ID.
order_shipments AS (
    SELECT
        ORDER_ID,
        COUNT(DISTINCT SHIPMENT_ID)                                     AS SHIPMENT_COUNT,
        COUNT(DISTINCT CASE WHEN IS_ON_TIME = FALSE THEN SHIPMENT_ID END)
            AS LATE_SHIPMENT_COUNT
    FROM order_shipment_pairs
    GROUP BY ORDER_ID
)

-- =============================================================================
-- FINAL ASSEMBLY
-- Join Branch 1 (50,000 rows) + Branch 2 (45,654 rows) + dimensions.
-- All joins are 1:1 or M:1 on a pre-established ORDER_ID grain.
-- =============================================================================
SELECT
    -- 1. Metadata / Identifiers
    orf.ORDER_ID,
    orf.ANALYSIS_AS_OF_DATE,

    -- 2. Order Attributes
    orf.CUSTOMER_ID,
    dc.CUSTOMER_NAME,
    dc.CUSTOMER_SEGMENT,
    orf.PLANT_ID,
    dp.PLANT_NAME,
    orf.ORDER_DATE,
    orf.REQUESTED_DELIVERY_DATE,

    -- 3. Fulfillment Classification
    CASE
        WHEN orf.CANCELLED_LINE_COUNT = orf.TOTAL_ORDER_LINE_COUNT
            THEN 'CANCELLED'
        WHEN orf.OUTSTANDING_QTY = 0
            THEN 'FULFILLED'
        WHEN orf.EFFECTIVE_SHIPPED_QTY > 0
            THEN 'PARTIALLY_FULFILLED'
        ELSE 'UNFULFILLED'
    END AS FULFILLMENT_STATE,

    -- 4. Quantity Metrics
    orf.TOTAL_ORDER_LINE_COUNT,
    orf.CANCELLED_LINE_COUNT,
    orf.TOTAL_ORDER_LINE_COUNT - orf.CANCELLED_LINE_COUNT
        AS ACTIVE_LINE_COUNT,
    orf.ORDERED_QTY,
    orf.ACTIVE_ORDERED_QTY,
    orf.RAW_SHIPPED_QTY,
    orf.EFFECTIVE_SHIPPED_QTY,
    orf.OUTSTANDING_QTY,
    orf.OVER_SHIPPED_QTY,
    ROUND(100.0 * orf.EFFECTIVE_SHIPPED_QTY
          / NULLIF(orf.ACTIVE_ORDERED_QTY, 0), 2)
        AS FULFILLMENT_PCT,

    -- 5. Value Metrics
    orf.ORDER_VALUE,
    orf.ACTIVE_ORDER_VALUE,
    orf.OUTSTANDING_VALUE,

    -- 6. Shipment Metrics
    COALESCE(os.SHIPMENT_COUNT, 0)       AS SHIPMENT_COUNT,
    COALESCE(os.LATE_SHIPMENT_COUNT, 0)  AS LATE_SHIPMENT_COUNT,

    -- 7. Delay Metrics
    orf.CURRENT_DELAY_DAYS,
    orf.MAX_DELIVERED_DELAY_DAYS,
    orf.LAST_ACTUAL_DELIVERY_DATE,

    -- 8. Explainability Flags
    CASE
        WHEN orf.CANCELLED_LINE_COUNT = orf.TOTAL_ORDER_LINE_COUNT
            THEN 'CANCELLED'
        WHEN orf.OUTSTANDING_QTY = 0
            THEN 'FULFILLED'
        WHEN orf.EFFECTIVE_SHIPPED_QTY > 0
            THEN 'PARTIALLY_FULFILLED'
        ELSE 'UNFULFILLED'
    END = 'FULFILLED'
        AS IS_FULFILLED,
    CASE
        WHEN orf.CANCELLED_LINE_COUNT = orf.TOTAL_ORDER_LINE_COUNT
            THEN 'CANCELLED'
        WHEN orf.OUTSTANDING_QTY = 0
            THEN 'FULFILLED'
        WHEN orf.EFFECTIVE_SHIPPED_QTY > 0
            THEN 'PARTIALLY_FULFILLED'
        ELSE 'UNFULFILLED'
    END = 'PARTIALLY_FULFILLED'
        AS IS_PARTIALLY_FULFILLED,
    CASE
        WHEN orf.CANCELLED_LINE_COUNT = orf.TOTAL_ORDER_LINE_COUNT
            THEN 'CANCELLED'
        WHEN orf.OUTSTANDING_QTY = 0
            THEN 'FULFILLED'
        WHEN orf.EFFECTIVE_SHIPPED_QTY > 0
            THEN 'PARTIALLY_FULFILLED'
        ELSE 'UNFULFILLED'
    END = 'UNFULFILLED'
        AS IS_UNFULFILLED,
    CASE
        WHEN orf.CANCELLED_LINE_COUNT = orf.TOTAL_ORDER_LINE_COUNT
            THEN 'CANCELLED'
        WHEN orf.OUTSTANDING_QTY = 0
            THEN 'FULFILLED'
        WHEN orf.EFFECTIVE_SHIPPED_QTY > 0
            THEN 'PARTIALLY_FULFILLED'
        ELSE 'UNFULFILLED'
    END = 'CANCELLED'
        AS IS_CANCELLED,
    orf.IS_CURRENT_LATE,
    orf.IS_DELIVERED_LATE,
    (orf.IS_CURRENT_LATE OR orf.IS_DELIVERED_LATE)
        AS IS_LATE,
    (COALESCE(os.LATE_SHIPMENT_COUNT, 0) > 0)
        AS HAS_DELAYED_SHIPMENT,
    (orf.OVER_SHIPPED_QTY > 0)
        AS HAS_OVER_SHIPMENT

FROM order_fulfillment orf
LEFT JOIN order_shipments os
    ON orf.ORDER_ID = os.ORDER_ID
LEFT JOIN SUPPLY_CHAIN_DW.SILVER.DIM_CUSTOMER dc
    ON orf.CUSTOMER_ID = dc.CUSTOMER_ID
LEFT JOIN SUPPLY_CHAIN_DW.SILVER.DIM_PLANT dp
    ON orf.PLANT_ID = dp.PLANT_ID;

-- ## Post-change validation
-- Run validations/gold/mart_order_fulfillment_checks.sql
-- Run validations/gold/mart_order_fulfillment_scenario_structural.sql
-- Run validations/gold/mart_order_fulfillment_scenario_behavioral.sql

-- ## Rollback / manual recovery
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT;
