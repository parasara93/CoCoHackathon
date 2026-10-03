-- =============================================================================
-- MART_ORDER_FULFILLMENT — Scenario Structural Validation (PASS/FAIL)
-- Target: SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT
-- Run after V2.5.0 is applied and VALIDATION.SCENARIO_AFFECTED_ENTITY is loaded.
-- =============================================================================
--
-- Verifies that all ground-truth ORDER_IDs exist in the mart.
-- Expected: 100% coverage (the mart contains every ORDER_ID from FACT_ORDER_LINE).

-- =============================================================================
-- 1. SC-000001 — Supplier Deterioration (3,104 affected orders)
-- =============================================================================
SELECT 'SC1_ORDER_COVERAGE' AS check_name,
  gt.GROUND_TRUTH_COUNT,
  gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT AS MATCHED_COUNT,
  orphan.UNMATCHED_COUNT,
  ROUND(100.0 * (gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT)
        / NULLIF(gt.GROUND_TRUTH_COUNT, 0), 2) AS COVERAGE_PCT,
  CASE WHEN orphan.UNMATCHED_COUNT = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM
  (SELECT COUNT(*) AS GROUND_TRUTH_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
   WHERE SCENARIO_ID = 'SC-000001' AND ENTITY_TYPE = 'ORDER') gt,
  (SELECT COUNT(*) AS UNMATCHED_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY sae
   WHERE sae.SCENARIO_ID = 'SC-000001' AND sae.ENTITY_TYPE = 'ORDER'
     AND NOT EXISTS (SELECT 1 FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT m
                     WHERE m.ORDER_ID = sae.ENTITY_ID)) orphan;

-- =============================================================================
-- 2. SC-000002 — Inventory Shortage (211 affected orders)
-- =============================================================================
SELECT 'SC2_ORDER_COVERAGE' AS check_name,
  gt.GROUND_TRUTH_COUNT,
  gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT AS MATCHED_COUNT,
  orphan.UNMATCHED_COUNT,
  ROUND(100.0 * (gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT)
        / NULLIF(gt.GROUND_TRUTH_COUNT, 0), 2) AS COVERAGE_PCT,
  CASE WHEN orphan.UNMATCHED_COUNT = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM
  (SELECT COUNT(*) AS GROUND_TRUTH_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
   WHERE SCENARIO_ID = 'SC-000002' AND ENTITY_TYPE = 'ORDER') gt,
  (SELECT COUNT(*) AS UNMATCHED_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY sae
   WHERE sae.SCENARIO_ID = 'SC-000002' AND sae.ENTITY_TYPE = 'ORDER'
     AND NOT EXISTS (SELECT 1 FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT m
                     WHERE m.ORDER_ID = sae.ENTITY_ID)) orphan;

-- =============================================================================
-- 3. SC-000003 — Plant Bottleneck (886 affected orders)
-- =============================================================================
SELECT 'SC3_ORDER_COVERAGE' AS check_name,
  gt.GROUND_TRUTH_COUNT,
  gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT AS MATCHED_COUNT,
  orphan.UNMATCHED_COUNT,
  ROUND(100.0 * (gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT)
        / NULLIF(gt.GROUND_TRUTH_COUNT, 0), 2) AS COVERAGE_PCT,
  CASE WHEN orphan.UNMATCHED_COUNT = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM
  (SELECT COUNT(*) AS GROUND_TRUTH_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
   WHERE SCENARIO_ID = 'SC-000003' AND ENTITY_TYPE = 'ORDER') gt,
  (SELECT COUNT(*) AS UNMATCHED_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY sae
   WHERE sae.SCENARIO_ID = 'SC-000003' AND sae.ENTITY_TYPE = 'ORDER'
     AND NOT EXISTS (SELECT 1 FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT m
                     WHERE m.ORDER_ID = sae.ENTITY_ID)) orphan;

-- =============================================================================
-- 4. SC-000004 — Logistics Disruption (47 affected shipments, traced to orders)
-- =============================================================================
WITH scenario_shipments AS (
    SELECT ENTITY_ID AS SHIPMENT_ID
    FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
    WHERE SCENARIO_ID = 'SC-000004' AND ENTITY_TYPE = 'SHIPMENT'
),
traced_orders AS (
    SELECT DISTINCT fol.ORDER_ID
    FROM scenario_shipments ss
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE fsl ON ss.SHIPMENT_ID = fsl.SHIPMENT_ID
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE fol ON fsl.ORDER_LINE_ID = fol.ORDER_LINE_ID
),
matched AS (
    SELECT t.ORDER_ID,
      CASE WHEN m.ORDER_ID IS NOT NULL THEN 1 ELSE 0 END AS IS_MATCHED
    FROM traced_orders t
    LEFT JOIN SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT m ON t.ORDER_ID = m.ORDER_ID
)
SELECT 'SC4_SHIPMENT_TRACED_ORDER_COVERAGE' AS check_name,
  (SELECT COUNT(*) FROM scenario_shipments) AS AFFECTED_SHIPMENT_COUNT,
  (SELECT COUNT(*) FROM traced_orders) AS TRACED_ORDER_COUNT,
  SUM(IS_MATCHED) AS MATCHED_ORDER_COUNT,
  COUNT(*) - SUM(IS_MATCHED) AS UNMATCHED_ORDER_COUNT,
  CASE WHEN COUNT(*) - SUM(IS_MATCHED) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM matched;

-- =============================================================================
-- 5. SC-000005 — Customer Impact (30,322 affected orders)
-- =============================================================================
SELECT 'SC5_ORDER_COVERAGE' AS check_name,
  gt.GROUND_TRUTH_COUNT,
  gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT AS MATCHED_COUNT,
  orphan.UNMATCHED_COUNT,
  ROUND(100.0 * (gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT)
        / NULLIF(gt.GROUND_TRUTH_COUNT, 0), 2) AS COVERAGE_PCT,
  CASE WHEN orphan.UNMATCHED_COUNT = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM
  (SELECT COUNT(*) AS GROUND_TRUTH_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
   WHERE SCENARIO_ID = 'SC-000005' AND ENTITY_TYPE = 'ORDER') gt,
  (SELECT COUNT(*) AS UNMATCHED_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY sae
   WHERE sae.SCENARIO_ID = 'SC-000005' AND sae.ENTITY_TYPE = 'ORDER'
     AND NOT EXISTS (SELECT 1 FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT m
                     WHERE m.ORDER_ID = sae.ENTITY_ID)) orphan;
