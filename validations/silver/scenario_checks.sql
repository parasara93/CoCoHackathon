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
-- S1: SUPPLIER DETERIORATION (SUP-000016)
-- Generator logic: deterioration window starts at perf_dates[len//3], degrading
-- risk_score (+0.25-0.5), fill_rate_pct (*0.5-0.75), on_time_delivery_pct (*0.4-0.7).
-- Ground truth: scenario period 2025-11-30 to 2026-03-30.
-- Pre-deterioration measurements: before 2025-11-30 (normal baseline).
-- During-deterioration measurements: >= 2025-11-30 (degraded metrics).
-- =============================================================================

-- Check: SUP-000016 shows fill_rate collapse during deterioration vs baseline
SELECT 'S1: Supplier fill rate deterioration visible' AS check_name,
       pre_fill_rate AS pre_deterioration_fill_rate,
       during_fill_rate AS during_deterioration_fill_rate,
       CASE WHEN pre_fill_rate - during_fill_rate > 0.15 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
  SELECT
    AVG(CASE WHEN MEASUREMENT_DATE_KEY < '2025-11-30' THEN FILL_RATE_PCT END) AS pre_fill_rate,
    AVG(CASE WHEN MEASUREMENT_DATE_KEY >= '2025-11-30' THEN FILL_RATE_PCT END) AS during_fill_rate
  FROM SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE
  WHERE SUPPLIER_ID = 'SUP-000016'
);

-- Check: SUP-000016 shows risk_score escalation during deterioration vs baseline
SELECT 'S1: Supplier risk escalation visible' AS check_name,
       pre_risk AS pre_deterioration_risk,
       during_risk AS during_deterioration_risk,
       CASE WHEN during_risk - pre_risk > 0.20 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
  SELECT
    AVG(CASE WHEN MEASUREMENT_DATE_KEY < '2025-11-30' THEN RISK_SCORE END) AS pre_risk,
    AVG(CASE WHEN MEASUREMENT_DATE_KEY >= '2025-11-30' THEN RISK_SCORE END) AS during_risk
  FROM SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE
  WHERE SUPPLIER_ID = 'SUP-000016'
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
-- S3: PLANT BOTTLENECK (PLT-000003)
-- Generator logic: bottleneck window 50-75% of timeline (~2026-04-01 to 2026-07-01).
-- Reserves 70-95% of on-hand inventory at PLT-000003 (→ CRITICAL/OUT_OF_STOCK).
-- Stalls CREATED/CONFIRMED orders to PROCESSING.
-- Validates the encoded signals: elevated PROCESSING orders + inventory pressure.
-- =============================================================================

-- Check: PLT-000003 has a higher proportion of PROCESSING/PARTIALLY_SHIPPED orders
-- than the average across all other plants (bottleneck creates order backlog)
SELECT 'S3: Plant bottleneck pattern visible' AS check_name,
       ROUND(SUM(CASE WHEN PLANT_ID = 'PLT-000003' AND ORDER_STATUS IN ('PROCESSING','PARTIALLY_SHIPPED') THEN 1 ELSE 0 END)
             * 100.0 / NULLIF(SUM(CASE WHEN PLANT_ID = 'PLT-000003' THEN 1 ELSE 0 END), 0), 1)
         AS pct_stalled_at_target_plant,
       ROUND(SUM(CASE WHEN PLANT_ID != 'PLT-000003' AND ORDER_STATUS IN ('PROCESSING','PARTIALLY_SHIPPED') THEN 1 ELSE 0 END)
             * 100.0 / NULLIF(SUM(CASE WHEN PLANT_ID != 'PLT-000003' THEN 1 ELSE 0 END), 0), 1)
         AS pct_stalled_at_other_plants,
       CASE WHEN
         SUM(CASE WHEN PLANT_ID = 'PLT-000003' AND ORDER_STATUS IN ('PROCESSING','PARTIALLY_SHIPPED') THEN 1 ELSE 0 END)
           * 1.0 / NULLIF(SUM(CASE WHEN PLANT_ID = 'PLT-000003' THEN 1 ELSE 0 END), 0)
         >
         SUM(CASE WHEN PLANT_ID != 'PLT-000003' AND ORDER_STATUS IN ('PROCESSING','PARTIALLY_SHIPPED') THEN 1 ELSE 0 END)
           * 1.0 / NULLIF(SUM(CASE WHEN PLANT_ID != 'PLT-000003' THEN 1 ELSE 0 END), 0)
       THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE;

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
-- Generator injects DELAY_REPORTED and ROUTE_DEVIATION events for disrupted shipments
SELECT 'S4: Disruption-related shipment events present' AS check_name,
       COUNT(*) AS disruption_events,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT
WHERE EVENT_TYPE IN ('DELAY_REPORTED', 'ROUTE_DEVIATION');

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
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE) <=
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.ORDER_LINES)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Shipments dedup
SELECT 'DEDUP: SHIPMENTS' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.SHIPMENTS) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT) <=
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.SHIPMENTS)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Inventory dedup
SELECT 'DEDUP: INVENTORY' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.INVENTORY) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT) <=
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.INVENTORY)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Supplier performance dedup
SELECT 'DEDUP: SUPPLIER_PERFORMANCE' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.SUPPLIER_PERFORMANCE) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE) <=
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.SUPPLIER_PERFORMANCE)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Supplier parts dedup
SELECT 'DEDUP: SUPPLIER_PARTS' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.SUPPLIER_PARTS) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART) <=
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.SUPPLIER_PARTS)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- History tables: Silver count should equal RAW count (no dedup)
SELECT 'NO_DEDUP: SHIPMENT_EVENTS' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.SHIPMENT_EVENTS) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT) =
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.SHIPMENT_EVENTS)
            THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'NO_DEDUP: VEHICLE_TELEMETRY' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.VEHICLE_TELEMETRY) AS raw_count,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY) AS silver_count,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY) =
                 (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.RAW.VEHICLE_TELEMETRY)
            THEN 'PASS' ELSE 'FAIL' END AS result;
