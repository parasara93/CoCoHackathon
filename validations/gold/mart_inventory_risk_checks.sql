-- =============================================================================
-- MART_INVENTORY_RISK Validation Checks
-- Data-relative: no fixed row counts; validates against current Silver state.
-- =============================================================================

-- ===== STRUCTURAL CHECKS =====

-- 1. Column count = 27 (24 original + 3 demand coverage from V3.7.0)
SELECT 'Column count = 27' AS check_name,
       COUNT(*) AS val,
       CASE WHEN COUNT(*) = 27 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'GOLD' AND TABLE_NAME = 'MART_INVENTORY_RISK'
  AND TABLE_CATALOG = 'SUPPLY_CHAIN_DW';

-- 2. Row count = FACT_INVENTORY_SNAPSHOT
SELECT 'Row count = FACT_INVENTORY_SNAPSHOT' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK) AS mart_rows,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT) AS silver_rows,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK)
                 = (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- 3. Grain uniqueness: one row per PLANT_ID + PART_ID
SELECT 'Grain uniqueness (PLANT_ID+PART_ID)' AS check_name,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT PLANT_ID || '|' || PART_ID) AS distinct_keys,
       CASE WHEN COUNT(*) = COUNT(DISTINCT PLANT_ID || '|' || PART_ID)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- =============================================================================
-- DAYS OF DEMAND COVERAGE (90D) CHECKS — V3.7.0
-- =============================================================================

-- 19. Column count updated to 27 (24 original + 3 demand coverage)
SELECT 'Column count = 27' AS check_name,
       (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'GOLD' AND TABLE_NAME = 'MART_INVENTORY_RISK') AS actual,
       27 AS expected,
       CASE WHEN (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.INFORMATION_SCHEMA.COLUMNS
                  WHERE TABLE_SCHEMA = 'GOLD' AND TABLE_NAME = 'MART_INVENTORY_RISK') = 27
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- 20. 90-day demand window: ORDER_DEMAND_QTY_90D is populated or NULL (no negatives)
SELECT 'Demand qty non-negative' AS check_name,
       SUM(CASE WHEN ORDER_DEMAND_QTY_90D < 0 THEN 1 ELSE 0 END) AS violations,
       CASE WHEN SUM(CASE WHEN ORDER_DEMAND_QTY_90D < 0 THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- 21. AVG_DAILY_ORDER_DEMAND_90D = ORDER_DEMAND_QTY_90D / 90 (within tolerance)
SELECT 'Daily demand formula' AS check_name,
       SUM(CASE WHEN ORDER_DEMAND_QTY_90D IS NOT NULL
                 AND ABS(AVG_DAILY_ORDER_DEMAND_90D - ROUND(ORDER_DEMAND_QTY_90D / 90.0, 4)) > 0.01
            THEN 1 ELSE 0 END) AS violations,
       CASE WHEN SUM(CASE WHEN ORDER_DEMAND_QTY_90D IS NOT NULL
                 AND ABS(AVG_DAILY_ORDER_DEMAND_90D - ROUND(ORDER_DEMAND_QTY_90D / 90.0, 4)) > 0.01
            THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- 22. DAYS_OF_DEMAND_COVERAGE_90D = AVAILABLE_QTY / (ORDER_DEMAND_QTY_90D / 90)
-- Uses raw demand_qty / 90 as denominator (matching the INSERT formula, not the rounded column)
SELECT 'Coverage formula' AS check_name,
       SUM(CASE WHEN ORDER_DEMAND_QTY_90D > 0
                 AND ABS(DAYS_OF_DEMAND_COVERAGE_90D
                       - ROUND(AVAILABLE_QTY / (ORDER_DEMAND_QTY_90D / 90.0), 4)) > 0.01
            THEN 1 ELSE 0 END) AS violations,
       CASE WHEN SUM(CASE WHEN ORDER_DEMAND_QTY_90D > 0
                 AND ABS(DAYS_OF_DEMAND_COVERAGE_90D
                       - ROUND(AVAILABLE_QTY / (ORDER_DEMAND_QTY_90D / 90.0), 4)) > 0.01
            THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- 23. Zero-demand handling: NULL coverage when no demand
SELECT 'Zero-demand = NULL coverage' AS check_name,
       SUM(CASE WHEN (ORDER_DEMAND_QTY_90D IS NULL OR ORDER_DEMAND_QTY_90D = 0)
                 AND DAYS_OF_DEMAND_COVERAGE_90D IS NOT NULL
            THEN 1 ELSE 0 END) AS violations,
       CASE WHEN SUM(CASE WHEN (ORDER_DEMAND_QTY_90D IS NULL OR ORDER_DEMAND_QTY_90D = 0)
                 AND DAYS_OF_DEMAND_COVERAGE_90D IS NOT NULL
            THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- 24. No negative coverage days
SELECT 'No negative coverage' AS check_name,
       SUM(CASE WHEN DAYS_OF_DEMAND_COVERAGE_90D < 0 THEN 1 ELSE 0 END) AS violations,
       CASE WHEN SUM(CASE WHEN DAYS_OF_DEMAND_COVERAGE_90D < 0 THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- 25. Demand qty reconciles to Silver (within matched plant+part population)
-- Note: Silver may have demand for plant+parts NOT in inventory mart; that's expected.
SELECT 'Demand reconciles to Silver (matched positions)' AS check_name,
       ABS(gold_total - silver_total) AS difference,
       CASE WHEN ABS(gold_total - silver_total) < 1 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT (SELECT SUM(ORDER_DEMAND_QTY_90D)
            FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK) AS gold_total,
           (SELECT SUM(fol.ORDERED_QTY)
            FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE fol
            JOIN (SELECT MAX(ORDER_DATE_KEY) AS md FROM SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE) a
              ON fol.ORDER_DATE_KEY >= DATEADD(DAY, -90, a.md)
            WHERE fol.LINE_STATUS != 'CANCELLED'
              AND EXISTS (SELECT 1 FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK inv
                          WHERE inv.PLANT_ID = fol.PLANT_ID AND inv.PART_ID = fol.PART_ID)
           ) AS silver_total
);

-- 4. No NULL composite key
SELECT 'No NULL PLANT_ID or PART_ID' AS check_name,
       SUM(CASE WHEN PLANT_ID IS NULL OR PART_ID IS NULL THEN 1 ELSE 0 END) AS null_count,
       CASE WHEN SUM(CASE WHEN PLANT_ID IS NULL OR PART_ID IS NULL THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- ===== SCENARIO S2: INVENTORY SHORTAGE PARTS =====

-- 5. All 4 scenario parts exist in mart
SELECT 'S2 parts present (4 parts)' AS check_name,
       COUNT(DISTINCT PART_ID) AS found_parts,
       CASE WHEN COUNT(DISTINCT PART_ID) = 4 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
WHERE PART_ID IN ('PRT-000037','PRT-000040','PRT-000084','PRT-000129');

-- 6. S2 parts have low inventory signals (at least some positions at risk)
SELECT 'S2 parts show inventory pressure' AS check_name,
       SUM(CASE WHEN NEEDS_REORDER OR BELOW_SAFETY_STOCK OR IS_OUT_OF_STOCK THEN 1 ELSE 0 END) AS at_risk_positions,
       CASE WHEN SUM(CASE WHEN NEEDS_REORDER OR BELOW_SAFETY_STOCK OR IS_OUT_OF_STOCK THEN 1 ELSE 0 END) > 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
WHERE PART_ID IN ('PRT-000037','PRT-000040','PRT-000084','PRT-000129');

-- ===== SCENARIO S3: PLANT BOTTLENECK (PLT-000003) =====

-- 7. PLT-000003 exists in mart
SELECT 'PLT-000003 exists' AS check_name,
       COUNT(*) AS positions,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
WHERE PLANT_ID = 'PLT-000003';

-- 8. PLT-000003 has elevated reservation pressure (higher reserved/on-hand ratio vs others)
SELECT 'PLT-000003 reservation pressure' AS check_name,
       ROUND(target_reserved_pct, 1) AS target_pct,
       ROUND(other_reserved_pct, 1) AS other_pct,
       CASE WHEN target_reserved_pct > other_reserved_pct THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT
        AVG(CASE WHEN PLANT_ID = 'PLT-000003' THEN RESERVED_QTY * 100.0 / NULLIF(ON_HAND_QTY, 0) END) AS target_reserved_pct,
        AVG(CASE WHEN PLANT_ID != 'PLT-000003' THEN RESERVED_QTY * 100.0 / NULLIF(ON_HAND_QTY, 0) END) AS other_reserved_pct
    FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
);

-- ===== FAN-OUT DETECTION =====

-- 9. No fan-out: grain check (duplicate composite keys)
SELECT 'No fan-out (grain)' AS check_name,
       COUNT(*) AS duplicates,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT PLANT_ID, PART_ID
    FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
    GROUP BY PLANT_ID, PART_ID
    HAVING COUNT(*) > 1
);

-- ===== FLAG RECONCILIATION TO SILVER =====

-- 10. NEEDS_REORDER matches Silver exactly
SELECT 'NEEDS_REORDER matches Silver' AS check_name,
       SUM(CASE WHEN m.NEEDS_REORDER != s.NEEDS_REORDER THEN 1 ELSE 0 END) AS mismatches,
       CASE WHEN SUM(CASE WHEN m.NEEDS_REORDER != s.NEEDS_REORDER THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK m
JOIN SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT s
    ON m.PLANT_ID = s.PLANT_ID AND m.PART_ID = s.PART_ID;

-- 11. BELOW_SAFETY_STOCK matches Silver exactly
SELECT 'BELOW_SAFETY_STOCK matches Silver' AS check_name,
       SUM(CASE WHEN m.BELOW_SAFETY_STOCK != s.BELOW_SAFETY_STOCK THEN 1 ELSE 0 END) AS mismatches,
       CASE WHEN SUM(CASE WHEN m.BELOW_SAFETY_STOCK != s.BELOW_SAFETY_STOCK THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK m
JOIN SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT s
    ON m.PLANT_ID = s.PLANT_ID AND m.PART_ID = s.PART_ID;

-- 12. ON_HAND_QTY matches Silver exactly
SELECT 'ON_HAND_QTY matches Silver' AS check_name,
       SUM(CASE WHEN m.ON_HAND_QTY != s.ON_HAND_QTY THEN 1 ELSE 0 END) AS mismatches,
       CASE WHEN SUM(CASE WHEN m.ON_HAND_QTY != s.ON_HAND_QTY THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK m
JOIN SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT s
    ON m.PLANT_ID = s.PLANT_ID AND m.PART_ID = s.PART_ID;

-- ===== SUPPLIER BACKUP COUNTS =====

-- 13. Max ACTIVE_SUPPLIER_COUNT is reasonable (bounded by DIM_SUPPLIER count)
SELECT 'Supplier count bounded' AS check_name,
       MAX(ACTIVE_SUPPLIER_COUNT) AS max_suppliers,
       CASE WHEN MAX(ACTIVE_SUPPLIER_COUNT) <= (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.DIM_SUPPLIER)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- 14. No positions have negative supplier count
SELECT 'Supplier count non-negative' AS check_name,
       SUM(CASE WHEN ACTIVE_SUPPLIER_COUNT < 0 THEN 1 ELSE 0 END) AS violations,
       CASE WHEN SUM(CASE WHEN ACTIVE_SUPPLIER_COUNT < 0 THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- ===== DERIVED COLUMN CONSISTENCY =====

-- 15. BELOW_SAFETY_STOCK_QTY formula check
SELECT 'BELOW_SAFETY_STOCK_QTY formula' AS check_name,
       SUM(CASE WHEN BELOW_SAFETY_STOCK_QTY != GREATEST(SAFETY_STOCK - AVAILABLE_QTY, 0) THEN 1 ELSE 0 END) AS violations,
       CASE WHEN SUM(CASE WHEN BELOW_SAFETY_STOCK_QTY != GREATEST(SAFETY_STOCK - AVAILABLE_QTY, 0) THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- 16. SHORTAGE_QTY formula check
SELECT 'SHORTAGE_QTY formula' AS check_name,
       SUM(CASE WHEN SHORTAGE_QTY != GREATEST(REORDER_POINT - AVAILABLE_QTY, 0) THEN 1 ELSE 0 END) AS violations,
       CASE WHEN SUM(CASE WHEN SHORTAGE_QTY != GREATEST(REORDER_POINT - AVAILABLE_QTY, 0) THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- 17. IS_OUT_OF_STOCK = (AVAILABLE_QTY = 0)
SELECT 'IS_OUT_OF_STOCK formula' AS check_name,
       SUM(CASE WHEN IS_OUT_OF_STOCK != (AVAILABLE_QTY = 0) THEN 1 ELSE 0 END) AS violations,
       CASE WHEN SUM(CASE WHEN IS_OUT_OF_STOCK != (AVAILABLE_QTY = 0) THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;

-- ===== NON-NEGATIVE CHECKS =====

-- 18. All qty/value columns non-negative
SELECT 'All metrics non-negative' AS check_name,
       SUM(CASE WHEN ON_HAND_QTY < 0 OR RESERVED_QTY < 0 OR AVAILABLE_QTY < 0
                  OR BELOW_SAFETY_STOCK_QTY < 0 OR SHORTAGE_QTY < 0
                  OR OUTSTANDING_ORDER_QTY < 0 OR OUTSTANDING_ORDER_VALUE < 0
            THEN 1 ELSE 0 END) AS violations,
       CASE WHEN SUM(CASE WHEN ON_HAND_QTY < 0 OR RESERVED_QTY < 0 OR AVAILABLE_QTY < 0
                  OR BELOW_SAFETY_STOCK_QTY < 0 OR SHORTAGE_QTY < 0
                  OR OUTSTANDING_ORDER_QTY < 0 OR OUTSTANDING_ORDER_VALUE < 0
            THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;
