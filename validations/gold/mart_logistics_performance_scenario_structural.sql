-- =============================================================================
-- MART_LOGISTICS_PERFORMANCE — Scenario Structural Validation (PASS/FAIL)
-- Target: SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
-- Run after V2.6.0 is applied and VALIDATION.SCENARIO_AFFECTED_ENTITY is loaded.
-- =============================================================================
--
-- SC-000004 Logistics Disruption:
-- 1 affected route (RTE-000164), 47 affected shipments.

-- =============================================================================
-- 1. Shipment coverage: all 47 affected SHIPMENT_IDs exist in the mart
-- =============================================================================
SELECT 'SC4_SHIPMENT_COVERAGE' AS check_name,
  gt.GROUND_TRUTH_COUNT,
  gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT AS MATCHED_COUNT,
  orphan.UNMATCHED_COUNT,
  ROUND(100.0 * (gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT)
        / NULLIF(gt.GROUND_TRUTH_COUNT, 0), 2) AS COVERAGE_PCT,
  CASE WHEN orphan.UNMATCHED_COUNT = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM
  (SELECT COUNT(*) AS GROUND_TRUTH_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
   WHERE SCENARIO_ID = 'SC-000004' AND ENTITY_TYPE = 'SHIPMENT') gt,
  (SELECT COUNT(*) AS UNMATCHED_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY sae
   WHERE sae.SCENARIO_ID = 'SC-000004' AND sae.ENTITY_TYPE = 'SHIPMENT'
     AND NOT EXISTS (SELECT 1 FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE m
                     WHERE m.SHIPMENT_ID = sae.ENTITY_ID)) orphan;

-- =============================================================================
-- 2. Route coverage: all 47 affected shipments have ROUTE_ID = 'RTE-000164'
-- =============================================================================
WITH sc4_shipments AS (
    SELECT sae.ENTITY_ID AS SHIPMENT_ID
    FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY sae
    WHERE sae.SCENARIO_ID = 'SC-000004' AND sae.ENTITY_TYPE = 'SHIPMENT'
),
route_check AS (
    SELECT
        s.SHIPMENT_ID,
        m.ROUTE_ID,
        CASE WHEN m.ROUTE_ID = 'RTE-000164' THEN 1 ELSE 0 END AS IS_EXPECTED_ROUTE
    FROM sc4_shipments s
    JOIN SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE m
        ON s.SHIPMENT_ID = m.SHIPMENT_ID
)
SELECT 'SC4_ROUTE_COVERAGE' AS check_name,
  COUNT(*) AS AFFECTED_SHIPMENT_COUNT,
  SUM(IS_EXPECTED_ROUTE) AS EXPECTED_ROUTE_MATCH_COUNT,
  COUNT(*) - SUM(IS_EXPECTED_ROUTE) AS ROUTE_MISMATCH_COUNT,
  ROUND(100.0 * SUM(IS_EXPECTED_ROUTE) / NULLIF(COUNT(*), 0), 2) AS COVERAGE_PCT,
  CASE WHEN COUNT(*) - SUM(IS_EXPECTED_ROUTE) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM route_check;
