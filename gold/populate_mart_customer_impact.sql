-- =============================================================================
-- Populate MART_CUSTOMER_IMPACT
-- =============================================================================
-- Populates SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT from Silver sources.
-- Reuses archived V2.1.0 design (34 columns).
--
-- Branch A: order/fulfillment aggregation (line → order → customer)
-- Branch B: distinct (CUSTOMER_ID, SHIPMENT_ID) for shipment statistics
--
-- Prerequisites: V3.5.0 (empty table) must be deployed.
-- Idempotent: TRUNCATE + INSERT pattern.
-- =============================================================================

TRUNCATE TABLE SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT;

INSERT INTO SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT (
    ANALYSIS_AS_OF_DATE,
    CUSTOMER_ID, CUSTOMER_NAME, CUSTOMER_SEGMENT,
    TOTAL_ORDER_COUNT, OPEN_ORDER_COUNT, FULFILLED_ORDER_COUNT,
    PARTIALLY_FULFILLED_ORDER_COUNT, UNFULFILLED_ORDER_COUNT, CANCELLED_ORDER_COUNT,
    CURRENT_LATE_ORDER_COUNT, DELIVERED_LATE_ORDER_COUNT, TOTAL_LATE_ORDER_COUNT,
    ACTIVE_ORDERED_QTY, ACTIVE_SHIPPED_QTY, OUTSTANDING_QTY, FULFILLMENT_PCT,
    ACTIVE_ORDER_VALUE, OUTSTANDING_VALUE, LATE_AFFECTED_ORDER_VALUE, OVERDUE_OUTSTANDING_VALUE,
    TOTAL_SHIPMENT_COUNT, LATE_SHIPMENT_COUNT,
    AVG_ORDER_DELAY_DAYS, MAX_ORDER_DELAY_DAYS, AVG_SHIPMENT_DELAY_HOURS, MAX_SHIPMENT_DELAY_HOURS,
    HAS_CURRENT_LATE_ORDER, HAS_DELIVERED_LATE_ORDER, HAS_LATE_ORDER,
    HAS_PARTIAL_FULFILLMENT, HAS_UNFULFILLED_ORDER, HAS_DELAYED_SHIPMENT, IS_IMPACTED
)
WITH analysis_anchor AS (
    SELECT MAX(LINE_UPDATED_AT)::DATE AS ANALYSIS_AS_OF_DATE
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE
),

-- =========================================================================
-- BRANCH A: Order / Fulfillment Aggregation
-- =========================================================================

-- Step A1: Aggregate shipment metrics to ORDER_LINE_ID.
-- Fan-out prevention: GROUP BY ORDER_LINE_ID → 1 row per line.
shipment_metrics_per_order_line AS (
    SELECT
        sl.ORDER_LINE_ID,
        SUM(sl.SHIPPED_QTY)                                            AS total_shipped_qty,
        MAX(s.ACTUAL_DELIVERY_AT)                                      AS latest_delivery_at,
        MAX(CASE WHEN s.IS_ON_TIME = FALSE THEN TRUE ELSE FALSE END)   AS has_late_shipment
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE sl
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT s ON sl.SHIPMENT_ID = s.SHIPMENT_ID
    GROUP BY sl.ORDER_LINE_ID
),

-- Step A2: Enrich order lines with shipment metrics + line-level flags.
-- LEFT JOIN 1:1 on ORDER_LINE_ID. Preserves unshipped lines.
order_line_enriched AS (
    SELECT
        ol.ORDER_LINE_ID, ol.ORDER_ID, ol.CUSTOMER_ID, ol.PLANT_ID, ol.PART_ID,
        ol.ORDER_DATE_KEY, ol.REQUESTED_DELIVERY_DATE_KEY, ol.ORDER_STATUS,
        ol.LINE_STATUS, ol.ORDERED_QTY, ol.UNIT_PRICE, ol.LINE_AMOUNT,
        sm.total_shipped_qty, sm.latest_delivery_at, a.ANALYSIS_AS_OF_DATE,
        CASE WHEN ol.LINE_STATUS = 'CANCELLED' THEN TRUE ELSE FALSE END AS is_cancelled,
        CASE
            WHEN ol.LINE_STATUS = 'CANCELLED' THEN 'CANCELLED'
            WHEN COALESCE(sm.total_shipped_qty, 0) = 0 THEN 'UNFULFILLED'
            WHEN sm.total_shipped_qty < ol.ORDERED_QTY THEN 'PARTIALLY_FULFILLED'
            ELSE 'FULLY_FULFILLED'
        END AS line_fill_status,
        CASE WHEN ol.LINE_STATUS = 'CANCELLED' THEN 0
             ELSE GREATEST(0, ol.ORDERED_QTY - COALESCE(sm.total_shipped_qty, 0))
        END AS outstanding_qty,
        CASE WHEN ol.LINE_STATUS NOT IN ('DELIVERED','CANCELLED')
                  AND ol.REQUESTED_DELIVERY_DATE_KEY < a.ANALYSIS_AS_OF_DATE
                  AND COALESCE(sm.total_shipped_qty, 0) < ol.ORDERED_QTY
             THEN TRUE ELSE FALSE END AS is_current_late,
        CASE WHEN ol.LINE_STATUS = 'DELIVERED'
                  AND sm.latest_delivery_at IS NOT NULL
                  AND sm.latest_delivery_at::DATE > ol.REQUESTED_DELIVERY_DATE_KEY
             THEN TRUE ELSE FALSE END AS is_delivered_late,
        CASE
            WHEN ol.LINE_STATUS = 'DELIVERED'
                 AND sm.latest_delivery_at IS NOT NULL
                 AND sm.latest_delivery_at::DATE > ol.REQUESTED_DELIVERY_DATE_KEY
            THEN DATEDIFF('DAY', ol.REQUESTED_DELIVERY_DATE_KEY, sm.latest_delivery_at::DATE)
            WHEN ol.LINE_STATUS NOT IN ('DELIVERED','CANCELLED')
                 AND ol.REQUESTED_DELIVERY_DATE_KEY < a.ANALYSIS_AS_OF_DATE
                 AND COALESCE(sm.total_shipped_qty, 0) < ol.ORDERED_QTY
            THEN DATEDIFF('DAY', ol.REQUESTED_DELIVERY_DATE_KEY, a.ANALYSIS_AS_OF_DATE)
            ELSE NULL
        END AS order_delay_days
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE ol
    CROSS JOIN analysis_anchor a
    LEFT JOIN shipment_metrics_per_order_line sm ON ol.ORDER_LINE_ID = sm.ORDER_LINE_ID
),

-- Step A3: Aggregate to ORDER_ID.
order_summary AS (
    SELECT
        ORDER_ID, CUSTOMER_ID, ANALYSIS_AS_OF_DATE,
        COUNT(*) AS total_lines,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS cancelled_line_count,
        SUM(CASE WHEN LINE_STATUS = 'DELIVERED' THEN 1 ELSE 0 END) AS delivered_line_count,
        SUM(CASE WHEN LINE_STATUS NOT IN ('DELIVERED','CANCELLED') THEN 1 ELSE 0 END) AS active_line_count,
        SUM(CASE WHEN line_fill_status = 'FULLY_FULFILLED' THEN 1 ELSE 0 END) AS fulfilled_line_count,
        SUM(CASE WHEN line_fill_status = 'PARTIALLY_FULFILLED' THEN 1 ELSE 0 END) AS partial_line_count,
        SUM(CASE WHEN line_fill_status = 'UNFULFILLED' THEN 1 ELSE 0 END) AS unfulfilled_line_count,
        MAX(CASE WHEN is_current_late THEN 1 ELSE 0 END) AS is_current_late_order_int,
        MAX(CASE WHEN is_delivered_late THEN 1 ELSE 0 END) AS is_delivered_late_order_int,
        SUM(CASE WHEN NOT is_cancelled THEN ORDERED_QTY ELSE 0 END) AS active_ordered_qty,
        SUM(CASE WHEN NOT is_cancelled THEN COALESCE(total_shipped_qty, 0) ELSE 0 END) AS active_shipped_qty,
        SUM(CASE WHEN NOT is_cancelled THEN outstanding_qty ELSE 0 END) AS outstanding_qty,
        SUM(CASE WHEN LINE_STATUS NOT IN ('DELIVERED','CANCELLED') THEN LINE_AMOUNT ELSE 0 END) AS active_order_value,
        SUM(CASE WHEN NOT is_cancelled THEN outstanding_qty * UNIT_PRICE ELSE 0 END) AS outstanding_value,
        SUM(CASE WHEN is_current_late THEN LINE_AMOUNT ELSE 0 END) AS late_affected_order_value,
        SUM(CASE WHEN is_current_late THEN outstanding_qty * UNIT_PRICE ELSE 0 END) AS overdue_outstanding_value,
        AVG(order_delay_days) AS avg_order_delay_days,
        MAX(order_delay_days) AS max_order_delay_days
    FROM order_line_enriched
    GROUP BY ORDER_ID, CUSTOMER_ID, ANALYSIS_AS_OF_DATE
),

-- Step A4: Aggregate to CUSTOMER_ID.
customer_orders AS (
    SELECT
        CUSTOMER_ID, ANALYSIS_AS_OF_DATE,
        COUNT(*) AS total_order_count,
        SUM(CASE WHEN active_line_count > 0 THEN 1 ELSE 0 END) AS open_order_count,
        SUM(CASE WHEN cancelled_line_count = total_lines THEN 1 ELSE 0 END) AS cancelled_order_count,
        SUM(CASE WHEN cancelled_line_count < total_lines
                      AND unfulfilled_line_count = 0 AND partial_line_count = 0 AND active_line_count = 0
                 THEN 1 ELSE 0 END) AS fulfilled_order_count,
        SUM(CASE WHEN cancelled_line_count < total_lines
                      AND (fulfilled_line_count > 0 OR partial_line_count > 0)
                      AND (unfulfilled_line_count > 0 OR active_line_count > 0 OR partial_line_count > 0)
                      AND NOT (unfulfilled_line_count = 0 AND partial_line_count = 0 AND active_line_count = 0)
                 THEN 1 ELSE 0 END) AS partially_fulfilled_order_count,
        SUM(CASE WHEN cancelled_line_count < total_lines
                      AND fulfilled_line_count = 0 AND partial_line_count = 0
                      AND (unfulfilled_line_count > 0 OR active_line_count > 0)
                      AND COALESCE(active_shipped_qty, 0) = 0
                 THEN 1 ELSE 0 END) AS unfulfilled_order_count,
        SUM(is_current_late_order_int) AS current_late_order_count,
        SUM(is_delivered_late_order_int) AS delivered_late_order_count,
        SUM(CASE WHEN is_current_late_order_int = 1 OR is_delivered_late_order_int = 1 THEN 1 ELSE 0 END)
            AS total_late_order_count,
        SUM(active_ordered_qty) AS active_ordered_qty,
        SUM(active_shipped_qty) AS active_shipped_qty,
        SUM(outstanding_qty) AS outstanding_qty,
        SUM(active_order_value) AS active_order_value,
        SUM(outstanding_value) AS outstanding_value,
        SUM(late_affected_order_value) AS late_affected_order_value,
        SUM(overdue_outstanding_value) AS overdue_outstanding_value,
        AVG(avg_order_delay_days) AS avg_order_delay_days,
        MAX(max_order_delay_days) AS max_order_delay_days
    FROM order_summary
    GROUP BY CUSTOMER_ID, ANALYSIS_AS_OF_DATE
),

-- =========================================================================
-- BRANCH B: Shipment Stats per CUSTOMER_ID
-- Fan-out prevention: SELECT DISTINCT (CUSTOMER_ID, SHIPMENT_ID, ...) then
-- GROUP BY CUSTOMER_ID.
-- =========================================================================
customer_shipment_stats AS (
    SELECT
        CUSTOMER_ID,
        COUNT(DISTINCT SHIPMENT_ID) AS total_shipment_count,
        COUNT(DISTINCT CASE WHEN IS_ON_TIME = FALSE THEN SHIPMENT_ID END) AS late_shipment_count,
        AVG(CASE WHEN shipment_delay_hours > 0 THEN shipment_delay_hours END) AS avg_shipment_delay_hours,
        MAX(shipment_delay_hours) AS max_shipment_delay_hours
    FROM (
        SELECT DISTINCT
            ol.CUSTOMER_ID, s.SHIPMENT_ID, s.IS_ON_TIME,
            CASE WHEN s.ACTUAL_DELIVERY_AT > s.PLANNED_DELIVERY_AT
                 THEN DATEDIFF('HOUR', s.PLANNED_DELIVERY_AT, s.ACTUAL_DELIVERY_AT)
                 ELSE NULL END AS shipment_delay_hours
        FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE sl
        JOIN SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE ol ON sl.ORDER_LINE_ID = ol.ORDER_LINE_ID
        JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT s ON sl.SHIPMENT_ID = s.SHIPMENT_ID
    ) deduped
    GROUP BY CUSTOMER_ID
)

-- =========================================================================
-- FINAL: DIM_CUSTOMER JOIN Branch A LEFT JOIN Branch B
-- All 1:1 on CUSTOMER_ID. No fan-out.
-- =========================================================================
SELECT
    co.ANALYSIS_AS_OF_DATE,
    dc.CUSTOMER_ID, dc.CUSTOMER_NAME, dc.CUSTOMER_SEGMENT,
    co.TOTAL_ORDER_COUNT, co.OPEN_ORDER_COUNT, co.FULFILLED_ORDER_COUNT,
    co.PARTIALLY_FULFILLED_ORDER_COUNT, co.UNFULFILLED_ORDER_COUNT, co.CANCELLED_ORDER_COUNT,
    co.CURRENT_LATE_ORDER_COUNT, co.DELIVERED_LATE_ORDER_COUNT, co.TOTAL_LATE_ORDER_COUNT,
    co.ACTIVE_ORDERED_QTY, co.ACTIVE_SHIPPED_QTY, co.OUTSTANDING_QTY,
    ROUND(100.0 * co.ACTIVE_SHIPPED_QTY / NULLIF(co.ACTIVE_ORDERED_QTY, 0), 2) AS FULFILLMENT_PCT,
    co.ACTIVE_ORDER_VALUE, co.OUTSTANDING_VALUE,
    co.LATE_AFFECTED_ORDER_VALUE, co.OVERDUE_OUTSTANDING_VALUE,
    COALESCE(cs.TOTAL_SHIPMENT_COUNT, 0), COALESCE(cs.LATE_SHIPMENT_COUNT, 0),
    co.AVG_ORDER_DELAY_DAYS, co.MAX_ORDER_DELAY_DAYS,
    cs.AVG_SHIPMENT_DELAY_HOURS, cs.MAX_SHIPMENT_DELAY_HOURS,
    (co.CURRENT_LATE_ORDER_COUNT > 0),
    (co.DELIVERED_LATE_ORDER_COUNT > 0),
    (co.TOTAL_LATE_ORDER_COUNT > 0),
    (co.PARTIALLY_FULFILLED_ORDER_COUNT > 0),
    (co.UNFULFILLED_ORDER_COUNT > 0),
    (COALESCE(cs.LATE_SHIPMENT_COUNT, 0) > 0),
    (co.TOTAL_LATE_ORDER_COUNT > 0
     OR co.PARTIALLY_FULFILLED_ORDER_COUNT > 0
     OR co.UNFULFILLED_ORDER_COUNT > 0
     OR COALESCE(cs.LATE_SHIPMENT_COUNT, 0) > 0)
FROM SUPPLY_CHAIN_DW.SILVER.DIM_CUSTOMER dc
JOIN customer_orders co ON dc.CUSTOMER_ID = co.CUSTOMER_ID
LEFT JOIN customer_shipment_stats cs ON dc.CUSTOMER_ID = cs.CUSTOMER_ID;
