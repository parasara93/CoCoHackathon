-- =============================================================================
-- MART_INVENTORY_RISK — Scenario Structural Validation (PASS/FAIL)
-- Target: SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
-- Run after V2.7.0 is applied and VALIDATION.SCENARIO_AFFECTED_ENTITY is loaded.
-- =============================================================================
--
-- SC-000002 Inventory Shortage: 4 affected parts, 8 affected plants.

-- =============================================================================
-- 1. Affected PART_ID coverage
-- =============================================================================
SELECT 'SC2_PART_COVERAGE' AS check_name,
  gt.GROUND_TRUTH_COUNT,
  gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT AS MATCHED_COUNT,
  orphan.UNMATCHED_COUNT,
  ROUND(100.0 * (gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT)
        / NULLIF(gt.GROUND_TRUTH_COUNT, 0), 2) AS COVERAGE_PCT,
  CASE WHEN orphan.UNMATCHED_COUNT = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM
  (SELECT COUNT(DISTINCT ENTITY_ID) AS GROUND_TRUTH_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
   WHERE SCENARIO_ID = 'SC-000002' AND ENTITY_TYPE = 'PART') gt,
  (SELECT COUNT(*) AS UNMATCHED_COUNT
   FROM (SELECT DISTINCT ENTITY_ID AS PART_ID
         FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
         WHERE SCENARIO_ID = 'SC-000002' AND ENTITY_TYPE = 'PART') sae
   WHERE NOT EXISTS (SELECT 1 FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK m
                     WHERE m.PART_ID = sae.PART_ID)) orphan;

-- =============================================================================
-- 2. Affected PLANT_ID coverage
-- =============================================================================
SELECT 'SC2_PLANT_COVERAGE' AS check_name,
  gt.GROUND_TRUTH_COUNT,
  gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT AS MATCHED_COUNT,
  orphan.UNMATCHED_COUNT,
  ROUND(100.0 * (gt.GROUND_TRUTH_COUNT - orphan.UNMATCHED_COUNT)
        / NULLIF(gt.GROUND_TRUTH_COUNT, 0), 2) AS COVERAGE_PCT,
  CASE WHEN orphan.UNMATCHED_COUNT = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM
  (SELECT COUNT(DISTINCT ENTITY_ID) AS GROUND_TRUTH_COUNT
   FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
   WHERE SCENARIO_ID = 'SC-000002' AND ENTITY_TYPE = 'PLANT') gt,
  (SELECT COUNT(*) AS UNMATCHED_COUNT
   FROM (SELECT DISTINCT ENTITY_ID AS PLANT_ID
         FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
         WHERE SCENARIO_ID = 'SC-000002' AND ENTITY_TYPE = 'PLANT') sae
   WHERE NOT EXISTS (SELECT 1 FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK m
                     WHERE m.PLANT_ID = sae.PLANT_ID)) orphan;

-- =============================================================================
-- 3. Affected PLANT_ID + PART_ID inventory-position coverage
--    Cross-product of affected parts × affected plants that exist in
--    FACT_INVENTORY_SNAPSHOT (16 expected from inspection).
-- =============================================================================
WITH sc2_parts AS (
    SELECT DISTINCT ENTITY_ID AS PART_ID
    FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
    WHERE SCENARIO_ID = 'SC-000002' AND ENTITY_TYPE = 'PART'
),
sc2_plants AS (
    SELECT DISTINCT ENTITY_ID AS PLANT_ID
    FROM SUPPLY_CHAIN_DW.VALIDATION.SCENARIO_AFFECTED_ENTITY
    WHERE SCENARIO_ID = 'SC-000002' AND ENTITY_TYPE = 'PLANT'
),
affected_positions AS (
    SELECT inv.PLANT_ID, inv.PART_ID
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT inv
    WHERE inv.PART_ID IN (SELECT PART_ID FROM sc2_parts)
      AND inv.PLANT_ID IN (SELECT PLANT_ID FROM sc2_plants)
),
matched AS (
    SELECT ap.PLANT_ID, ap.PART_ID,
      CASE WHEN m.PLANT_ID IS NOT NULL THEN 1 ELSE 0 END AS IS_MATCHED
    FROM affected_positions ap
    LEFT JOIN SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK m
        ON ap.PLANT_ID = m.PLANT_ID AND ap.PART_ID = m.PART_ID
)
SELECT 'SC2_POSITION_COVERAGE' AS check_name,
  COUNT(*) AS GROUND_TRUTH_COUNT,
  SUM(IS_MATCHED) AS MATCHED_COUNT,
  COUNT(*) - SUM(IS_MATCHED) AS UNMATCHED_COUNT,
  ROUND(100.0 * SUM(IS_MATCHED) / NULLIF(COUNT(*), 0), 2) AS COVERAGE_PCT,
  CASE WHEN COUNT(*) - SUM(IS_MATCHED) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM matched;
