-- =============================================================================
-- SCENARIO PRESERVATION CHECKS
-- Validates that synthetic scenario behavior is visible in Silver data
-- without using scenario labels in transformation logic.
--
-- These queries confirm the data patterns injected by the 5 scenario types
-- are preserved through the Silver layer. They do NOT reference
-- scenario_ground_truth or embed scenario IDs.
-- =============================================================================

-- =============================================================================
-- S1: SUPPLIER DETERIORATION
-- Expected: Some suppliers show declining quality_score and on_time_delivery_pct
--           over time, with risk_score increasing.
-- =============================================================================

-- Check: at least one supplier has a measurable quality decline
-- (first-half avg quality > second-half avg quality by meaningful margin)
SELECT 'S1: Supplier quality deterioration visible' AS check_name,
       COUNT(*) AS suppliers_with_decline,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
  SELECT
    SUPPLIER_ID,
    AVG(CASE WHEN MEASUREMENT_DATE_KEY < '2026-04-01' THEN QUALITY_SCORE END) AS early_quality,
    AVG(CASE WHEN MEASUREMENT_DATE_KEY >= '2026-04-01' THEN QUALITY_SCORE END) AS late_quality
  FROM SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE
  GROUP BY SUPPLIER_ID
  HAVING early_quality IS NOT NULL AND late_quality IS NOT NULL
     AND early_quality - late_quality > 0.05
);

-- Check: at least one supplier has increasing risk score
SELECT 'S1: Supplier risk escalation visible' AS check_name,
       COUNT(*) AS suppliers_with_escalation,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
  SELECT
    SUPPLIER_ID,
    AVG(CASE WHEN MEASUREMENT_DATE_KEY < '2026-04-01' THEN RISK_SCORE END) AS early_risk,
    AVG(CASE WHEN MEASUREMENT_DATE_KEY >= '2026-04-01' THEN RISK_SCORE END) AS late_risk
  FROM SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE
  GROUP BY SUPPLIER_ID
  HAVING early_risk IS NOT NULL AND late_risk IS NOT NULL
     AND late_risk - early_risk > 0.05
);

-- =============================================================================
-- S2: INVENTORY SHORTAGE
-- Expected: Some plant+part combos show very low inventory with
--           NEEDS_REORDER=TRUE and/or BELOW_SAFETY_STOCK=TRUE.
-- =============================================================================

-- Check: meaningful proportion of items need reorder
SELECT 'S2: Inventory reorder signals present' AS check_name,
       SUM(CASE WHEN NEEDS_REORDER THEN 1 ELSE 0 END) AS needs_reorder_count,
       COUNT(*) AS total_count,
       CASE WHEN SUM(CASE WHEN NEEDS_REORDER THEN 1 ELSE 0 END) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT;

-- Check: some items are below safety stock (more severe)
SELECT 'S2: Below safety stock items present' AS check_name,
       SUM(CASE WHEN BELOW_SAFETY_STOCK THEN 1 ELSE 0 END) AS below_safety_count,
       COUNT(*) AS total_count,
       CASE WHEN SUM(CASE WHEN BELOW_SAFETY_STOCK THEN 1 ELSE 0 END) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT;

-- =============================================================================
-- S3: PLANT BOTTLENECK
-- Expected: Some plants have disproportionately high order volumes relative
--           to capacity, creating visible congestion patterns.
-- =============================================================================

-- Check: at least one plant has order volume exceeding capacity proxy
SELECT 'S3: Plant bottleneck pattern visible' AS check_name,
       COUNT(*) AS congested_plants,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
  SELECT
    f.PLANT_ID,
    p.CAPACITY_UNITS,
    COUNT(DISTINCT f.ORDER_ID) AS order_count,
    SUM(f.ORDERED_QTY) AS total_qty_ordered
  FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE f
  JOIN SUPPLY_CHAIN_DW.SILVER.DIM_PLANT p ON f.PLANT_ID = p.PLANT_ID
  GROUP BY f.PLANT_ID, p.CAPACITY_UNITS
  HAVING total_qty_ordered > CAPACITY_UNITS * 10
);

-- =============================================================================
-- S4: LOGISTICS DISRUPTION
-- Expected: Some shipments have significant late delivery, high transit
--           hours vs. planned, and IS_ON_TIME = FALSE.
-- =============================================================================

-- Check: late shipments exist with significant delay
SELECT 'S4: Late shipments with significant delay' AS check_name,
       COUNT(*) AS significantly_late,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT
WHERE IS_ON_TIME = FALSE
  AND ACTUAL_TRANSIT_HOURS > PLANNED_TRANSIT_HOURS * 1.2;

-- Check: shipment events show disruption-type events
SELECT 'S4: Disruption-related shipment events present' AS check_name,
       COUNT(*) AS disruption_events,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT
WHERE EVENT_TYPE IN ('DELAY', 'EXCEPTION', 'REROUTE', 'WEATHER_DELAY', 'CUSTOMS_HOLD');

-- Check: telemetry shows stopped vehicles (speed 0 for extended periods)
SELECT 'S4: Vehicle telemetry shows stopped vehicles' AS check_name,
       COUNT(*) AS stopped_readings,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY
WHERE SPEED_KMPH = 0 AND VEHICLE_STATUS != 'PARKED';

-- =============================================================================
-- S5: DOWNSTREAM CUSTOMER IMPACT
-- Expected: Customers affected by upstream scenarios show order cancellations,
--           partial fulfillment, or delayed delivery patterns.
-- =============================================================================

-- Check: cancelled or partially fulfilled order lines exist
SELECT 'S5: Cancelled/backorder line statuses present' AS check_name,
       COUNT(*) AS affected_lines,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE
WHERE LINE_STATUS IN ('CANCELLED', 'BACKORDERED', 'PARTIALLY_SHIPPED');

-- Check: some customers have multiple late deliveries
SELECT 'S5: Customers with repeated late deliveries' AS check_name,
       COUNT(*) AS affected_customers,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
  SELECT ol.CUSTOMER_ID, COUNT(*) AS late_count
  FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE sl
  JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT s ON sl.SHIPMENT_ID = s.SHIPMENT_ID
  JOIN SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE ol ON sl.ORDER_LINE_ID = ol.ORDER_LINE_ID
  WHERE s.IS_ON_TIME = FALSE
  GROUP BY ol.CUSTOMER_ID
  HAVING late_count >= 3
);

-- =============================================================================
-- DEDUPLICATION VERIFICATION
-- Confirm Silver row counts are less than or equal to RAW (verifies dedup worked)
-- =============================================================================

-- Order lines dedup: Silver should have fewer rows than RAW
SELECT 'DEDUP: ORDER_LINES' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.ORDER_LINES) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE) <=
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.ORDER_LINES)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Shipments dedup
SELECT 'DEDUP: SHIPMENTS' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.SHIPMENTS) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT) <=
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.SHIPMENTS)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Inventory dedup
SELECT 'DEDUP: INVENTORY' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.INVENTORY) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT) <=
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.INVENTORY)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Supplier performance dedup
SELECT 'DEDUP: SUPPLIER_PERFORMANCE' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.SUPPLIER_PERFORMANCE) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE) <=
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.SUPPLIER_PERFORMANCE)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Supplier parts dedup
SELECT 'DEDUP: SUPPLIER_PARTS' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.SUPPLIER_PARTS) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART) <=
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.SUPPLIER_PARTS)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- History tables: Silver count should equal RAW count (no dedup)
SELECT 'NO_DEDUP: SHIPMENT_EVENTS' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.SHIPMENT_EVENTS) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT) =
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.SHIPMENT_EVENTS)
            THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'NO_DEDUP: VEHICLE_TELEMETRY' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.VEHICLE_TELEMETRY) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY) =
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_RAW_DATASET.RAW.VEHICLE_TELEMETRY)
            THEN 'PASS' ELSE 'FAIL' END AS result;
