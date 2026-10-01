-- =============================================================================
-- V2.1.0 — Create MART_CUSTOMER_IMPACT
-- =============================================================================
--
-- ## Change purpose
-- First Gold analytical mart: customer-level supply-chain impact summary.
-- Answers: which customers are affected by execution problems, how severely,
-- and what observable operational conditions explain that impact.
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT
--
-- ## Grain
-- One row per CUSTOMER_ID (1,500 expected rows)
--
-- ## Design reference
-- 34-column v1 contract approved in design phase.
-- Branch A: order/fulfillment aggregation (shipment_line → order_line → order → customer)
-- Branch B: distinct (CUSTOMER_ID, SHIPMENT_ID) for shipment statistics
--
-- ## Preconditions
-- V2.0.0 (GOLD schema) must be applied.
-- Silver baseline tables must exist in SUPPLY_CHAIN_DW.SILVER.
--
-- ## DDL

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT AS

WITH analysis_anchor AS (
    -- Deterministic as-of date derived from the dataset itself.
    -- All lateness and exposure calculations use this instead of CURRENT_DATE.
    SELECT MAX(LINE_UPDATED_AT)::DATE AS ANALYSIS_AS_OF_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE
),

-- =============================================================================
-- BRANCH A: Order / Fulfillment Aggregation
-- =============================================================================

-- Step A1: Aggregate shipment metrics to ORDER_LINE_ID grain.
-- Collapses the 1:N shipment-line-to-order-line relationship (avg 1.72, max 8).
shipment_metrics_per_order_line AS (
    SELECT
        sl.ORDER_LINE_ID,
        SUM(sl.SHIPPED_QTY)                                            AS total_shipped_qty,
        MAX(s.ACTUAL_DELIVERY_AT)                                      AS latest_delivery_at,
        MAX(CASE WHEN s.IS_ON_TIME = FALSE THEN TRUE ELSE FALSE END)   AS has_late_shipment
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE sl
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT s
        ON sl.SHIPMENT_ID = s.SHIPMENT_ID
    GROUP BY sl.ORDER_LINE_ID
),

-- Step A2: Enrich order lines with shipment metrics and derive line-level flags.
-- LEFT JOIN ensures unshipped lines (45,016) are retained with NULLs.
-- Join is 1:1 on ORDER_LINE_ID (guaranteed by pre-aggregation).
order_line_enriched AS (
    SELECT
        ol.ORDER_LINE_ID,
        ol.ORDER_ID,
        ol.CUSTOMER_ID,
        ol.PLANT_ID,
        ol.PART_ID,
        ol.ORDER_DATE_KEY,
        ol.REQUESTED_DELIVERY_DATE_KEY,
        ol.ORDER_STATUS,
        ol.LINE_STATUS,
        ol.ORDERED_QTY,
        ol.UNIT_PRICE,
        ol.LINE_AMOUNT,
        sm.total_shipped_qty,
        sm.latest_delivery_at,
        a.ANALYSIS_AS_OF_DATE,

        -- Line classification
        CASE WHEN ol.LINE_STATUS = 'CANCELLED' THEN TRUE ELSE FALSE END
            AS is_cancelled,

        -- Fill status (non-cancelled lines only)
        CASE
            WHEN ol.LINE_STATUS = 'CANCELLED' THEN 'CANCELLED'
            WHEN COALESCE(sm.total_shipped_qty, 0) = 0 THEN 'UNFULFILLED'
            WHEN sm.total_shipped_qty < ol.ORDERED_QTY THEN 'PARTIALLY_FULFILLED'
            ELSE 'FULLY_FULFILLED'
        END AS line_fill_status,

        -- Outstanding quantity (non-cancelled only, floored at 0)
        CASE WHEN ol.LINE_STATUS = 'CANCELLED' THEN 0
             ELSE GREATEST(0, ol.ORDERED_QTY - COALESCE(sm.total_shipped_qty, 0))
        END AS outstanding_qty,

        -- Current late: active, past due, unfulfilled demand
        CASE
            WHEN ol.LINE_STATUS NOT IN ('DELIVERED', 'CANCELLED')
                 AND ol.REQUESTED_DELIVERY_DATE_KEY < a.ANALYSIS_AS_OF_DATE
                 AND COALESCE(sm.total_shipped_qty, 0) < ol.ORDERED_QTY
            THEN TRUE ELSE FALSE
        END AS is_current_late,

        -- Delivered late: delivered but after requested date
        CASE
            WHEN ol.LINE_STATUS = 'DELIVERED'
                 AND sm.latest_delivery_at IS NOT NULL
                 AND sm.latest_delivery_at::DATE > ol.REQUESTED_DELIVERY_DATE_KEY
            THEN TRUE ELSE FALSE
        END AS is_delivered_late,

        -- Order delay days
        CASE
            -- Delivered late: realized delay
            WHEN ol.LINE_STATUS = 'DELIVERED'
                 AND sm.latest_delivery_at IS NOT NULL
                 AND sm.latest_delivery_at::DATE > ol.REQUESTED_DELIVERY_DATE_KEY
            THEN DATEDIFF('DAY', ol.REQUESTED_DELIVERY_DATE_KEY, sm.latest_delivery_at::DATE)
            -- Current late: ongoing delay measured against analysis date
            WHEN ol.LINE_STATUS NOT IN ('DELIVERED', 'CANCELLED')
                 AND ol.REQUESTED_DELIVERY_DATE_KEY < a.ANALYSIS_AS_OF_DATE
                 AND COALESCE(sm.total_shipped_qty, 0) < ol.ORDERED_QTY
            THEN DATEDIFF('DAY', ol.REQUESTED_DELIVERY_DATE_KEY, a.ANALYSIS_AS_OF_DATE)
            ELSE NULL
        END AS order_delay_days

    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE ol
    CROSS JOIN analysis_anchor a
    LEFT JOIN shipment_metrics_per_order_line sm
        ON ol.ORDER_LINE_ID = sm.ORDER_LINE_ID
),

-- Step A3: Aggregate to ORDER_ID grain with deterministic order-level states.
order_summary AS (
    SELECT
        ORDER_ID,
        CUSTOMER_ID,
        ANALYSIS_AS_OF_DATE,

        -- Line counts for order state derivation
        COUNT(*)                                                                AS total_lines,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END)                          AS cancelled_line_count,
        SUM(CASE WHEN LINE_STATUS = 'DELIVERED' THEN 1 ELSE 0 END)             AS delivered_line_count,
        SUM(CASE WHEN LINE_STATUS NOT IN ('DELIVERED','CANCELLED') THEN 1 ELSE 0 END) AS active_line_count,

        -- Fill status counts (non-cancelled lines)
        SUM(CASE WHEN line_fill_status = 'FULLY_FULFILLED' THEN 1 ELSE 0 END)      AS fulfilled_line_count,
        SUM(CASE WHEN line_fill_status = 'PARTIALLY_FULFILLED' THEN 1 ELSE 0 END)  AS partial_line_count,
        SUM(CASE WHEN line_fill_status = 'UNFULFILLED' THEN 1 ELSE 0 END)          AS unfulfilled_line_count,

        -- Order-level lateness flags
        MAX(CASE WHEN is_current_late THEN 1 ELSE 0 END)    AS is_current_late_order_int,
        MAX(CASE WHEN is_delivered_late THEN 1 ELSE 0 END)   AS is_delivered_late_order_int,

        -- Quantity metrics (non-cancelled lines)
        SUM(CASE WHEN NOT is_cancelled THEN ORDERED_QTY ELSE 0 END)                        AS active_ordered_qty,
        SUM(CASE WHEN NOT is_cancelled THEN COALESCE(total_shipped_qty, 0) ELSE 0 END)     AS active_shipped_qty,
        SUM(CASE WHEN NOT is_cancelled THEN outstanding_qty ELSE 0 END)                     AS outstanding_qty,

        -- Value metrics
        SUM(CASE WHEN LINE_STATUS NOT IN ('DELIVERED','CANCELLED') THEN LINE_AMOUNT ELSE 0 END)  AS active_order_value,
        SUM(CASE WHEN NOT is_cancelled THEN outstanding_qty * UNIT_PRICE ELSE 0 END)             AS outstanding_value,
        SUM(CASE WHEN is_current_late THEN LINE_AMOUNT ELSE 0 END)                               AS late_affected_order_value,
        SUM(CASE WHEN is_current_late THEN outstanding_qty * UNIT_PRICE ELSE 0 END)              AS overdue_outstanding_value,

        -- Delay metrics
        AVG(order_delay_days)   AS avg_order_delay_days,
        MAX(order_delay_days)   AS max_order_delay_days

    FROM order_line_enriched
    GROUP BY ORDER_ID, CUSTOMER_ID, ANALYSIS_AS_OF_DATE
),

-- Step A4: Aggregate orders to CUSTOMER_ID grain.
customer_orders AS (
    SELECT
        CUSTOMER_ID,
        ANALYSIS_AS_OF_DATE,

        -- Order counts
        COUNT(*)                                                                    AS total_order_count,
        SUM(CASE WHEN active_line_count > 0 THEN 1 ELSE 0 END)                     AS open_order_count,

        -- Order fill status
        SUM(CASE
            WHEN cancelled_line_count = total_lines THEN 1 ELSE 0 END)              AS cancelled_order_count,
        SUM(CASE
            WHEN cancelled_line_count < total_lines
                 AND unfulfilled_line_count = 0
                 AND partial_line_count = 0
                 AND active_line_count = 0
            THEN 1 ELSE 0 END)                                                      AS fulfilled_order_count,
        SUM(CASE
            WHEN cancelled_line_count < total_lines
                 AND (fulfilled_line_count > 0 OR partial_line_count > 0)
                 AND (unfulfilled_line_count > 0 OR active_line_count > 0
                      OR partial_line_count > 0)
                 AND NOT (unfulfilled_line_count = 0 AND partial_line_count = 0 AND active_line_count = 0)
            THEN 1 ELSE 0 END)                                                      AS partially_fulfilled_order_count,
        SUM(CASE
            WHEN cancelled_line_count < total_lines
                 AND fulfilled_line_count = 0
                 AND partial_line_count = 0
                 AND (unfulfilled_line_count > 0 OR active_line_count > 0)
                 AND COALESCE(active_shipped_qty, 0) = 0
            THEN 1 ELSE 0 END)                                                      AS unfulfilled_order_count,

        -- Lateness counts
        SUM(is_current_late_order_int)                                              AS current_late_order_count,
        SUM(is_delivered_late_order_int)                                             AS delivered_late_order_count,
        SUM(CASE
            WHEN is_current_late_order_int = 1 OR is_delivered_late_order_int = 1
            THEN 1 ELSE 0 END)                                                      AS total_late_order_count,

        -- Quantity metrics
        SUM(active_ordered_qty)                                                     AS active_ordered_qty,
        SUM(active_shipped_qty)                                                     AS active_shipped_qty,
        SUM(outstanding_qty)                                                        AS outstanding_qty,

        -- Value metrics
        SUM(active_order_value)                                                     AS active_order_value,
        SUM(outstanding_value)                                                      AS outstanding_value,
        SUM(late_affected_order_value)                                              AS late_affected_order_value,
        SUM(overdue_outstanding_value)                                              AS overdue_outstanding_value,

        -- Delay metrics (averaged across all late lines for this customer)
        AVG(avg_order_delay_days)                                                   AS avg_order_delay_days,
        MAX(max_order_delay_days)                                                   AS max_order_delay_days

    FROM order_summary
    GROUP BY CUSTOMER_ID, ANALYSIS_AS_OF_DATE
),

-- =============================================================================
-- BRANCH B: Distinct (CUSTOMER_ID, SHIPMENT_ID) for Shipment Statistics
-- =============================================================================

-- Resolves shipment metrics at the correct grain.
-- One shipment can serve multiple customers (up to 5 observed).
-- Delay hours computed once per (CUSTOMER_ID, SHIPMENT_ID), not per order line.
customer_shipment_stats AS (
    SELECT
        CUSTOMER_ID,
        COUNT(DISTINCT SHIPMENT_ID)                                                          AS total_shipment_count,
        COUNT(DISTINCT CASE WHEN IS_ON_TIME = FALSE THEN SHIPMENT_ID END)                    AS late_shipment_count,
        AVG(CASE WHEN shipment_delay_hours > 0 THEN shipment_delay_hours END)                AS avg_shipment_delay_hours,
        MAX(shipment_delay_hours)                                                            AS max_shipment_delay_hours
    FROM (
        SELECT DISTINCT
            ol.CUSTOMER_ID,
            s.SHIPMENT_ID,
            s.IS_ON_TIME,
            CASE
                WHEN s.ACTUAL_DELIVERY_AT > s.PLANNED_DELIVERY_AT
                THEN DATEDIFF('HOUR', s.PLANNED_DELIVERY_AT, s.ACTUAL_DELIVERY_AT)
                ELSE NULL
            END AS shipment_delay_hours
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE sl
        JOIN SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE ol
            ON sl.ORDER_LINE_ID = ol.ORDER_LINE_ID
        JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT s
            ON sl.SHIPMENT_ID = s.SHIPMENT_ID
    ) deduped
    GROUP BY CUSTOMER_ID
)

-- =============================================================================
-- FINAL: Join Branch A + Branch B + DIM_CUSTOMER
-- =============================================================================

SELECT
    -- Meta
    co.ANALYSIS_AS_OF_DATE,

    -- Customer attributes
    dc.CUSTOMER_ID,
    dc.CUSTOMER_NAME,
    dc.CUSTOMER_SEGMENT,

    -- Order counts
    co.TOTAL_ORDER_COUNT,
    co.OPEN_ORDER_COUNT,
    co.FULFILLED_ORDER_COUNT,
    co.PARTIALLY_FULFILLED_ORDER_COUNT,
    co.UNFULFILLED_ORDER_COUNT,
    co.CANCELLED_ORDER_COUNT,
    co.CURRENT_LATE_ORDER_COUNT,
    co.DELIVERED_LATE_ORDER_COUNT,
    co.TOTAL_LATE_ORDER_COUNT,

    -- Quantity metrics
    co.ACTIVE_ORDERED_QTY,
    co.ACTIVE_SHIPPED_QTY,
    co.OUTSTANDING_QTY,
    ROUND(100.0 * co.ACTIVE_SHIPPED_QTY / NULLIF(co.ACTIVE_ORDERED_QTY, 0), 2)
        AS FULFILLMENT_PCT,

    -- Value metrics
    co.ACTIVE_ORDER_VALUE,
    co.OUTSTANDING_VALUE,
    co.LATE_AFFECTED_ORDER_VALUE,
    co.OVERDUE_OUTSTANDING_VALUE,

    -- Shipment metrics (Branch B)
    COALESCE(cs.TOTAL_SHIPMENT_COUNT, 0)     AS TOTAL_SHIPMENT_COUNT,
    COALESCE(cs.LATE_SHIPMENT_COUNT, 0)      AS LATE_SHIPMENT_COUNT,

    -- Delay metrics
    co.AVG_ORDER_DELAY_DAYS,
    co.MAX_ORDER_DELAY_DAYS,
    cs.AVG_SHIPMENT_DELAY_HOURS,
    cs.MAX_SHIPMENT_DELAY_HOURS,

    -- Explainability flags
    (co.CURRENT_LATE_ORDER_COUNT > 0)        AS HAS_CURRENT_LATE_ORDER,
    (co.DELIVERED_LATE_ORDER_COUNT > 0)       AS HAS_DELIVERED_LATE_ORDER,
    (co.TOTAL_LATE_ORDER_COUNT > 0)           AS HAS_LATE_ORDER,
    (co.PARTIALLY_FULFILLED_ORDER_COUNT > 0)  AS HAS_PARTIAL_FULFILLMENT,
    (co.UNFULFILLED_ORDER_COUNT > 0)          AS HAS_UNFULFILLED_ORDER,
    (COALESCE(cs.LATE_SHIPMENT_COUNT, 0) > 0) AS HAS_DELAYED_SHIPMENT,
    (co.TOTAL_LATE_ORDER_COUNT > 0
     OR co.PARTIALLY_FULFILLED_ORDER_COUNT > 0
     OR co.UNFULFILLED_ORDER_COUNT > 0
     OR COALESCE(cs.LATE_SHIPMENT_COUNT, 0) > 0) AS IS_IMPACTED

FROM SUPPLY_CHAIN_DW.SILVER.DIM_CUSTOMER dc
JOIN customer_orders co
    ON dc.CUSTOMER_ID = co.CUSTOMER_ID
LEFT JOIN customer_shipment_stats cs
    ON dc.CUSTOMER_ID = cs.CUSTOMER_ID;

-- ## Post-change validation
-- See validations/gold/mart_customer_impact_checks.sql

-- ## Rollback / manual recovery
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT;
