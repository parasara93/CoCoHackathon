-- =============================================================================
-- Validation checks for MART_LANDED_COST
-- =============================================================================
-- Run after gold/populate_mart_landed_cost.sql to verify data quality.
-- Each check returns check_name, metric(s), and PASS/FAIL.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Structural: column count
-- ---------------------------------------------------------------------------
SELECT
    'column_count' AS check_name,
    COUNT(*)       AS actual_columns,
    12             AS expected_columns,
    CASE WHEN COUNT(*) = 12 THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'GOLD' AND TABLE_NAME = 'MART_LANDED_COST';

-- ---------------------------------------------------------------------------
-- 2. Grain uniqueness: SUPPLIER_ID + PART_ID
-- ---------------------------------------------------------------------------
SELECT
    'grain_uniqueness' AS check_name,
    COUNT(*)           AS total_rows,
    COUNT(DISTINCT SUPPLIER_ID || '|' || PART_ID) AS distinct_keys,
    CASE WHEN COUNT(*) = COUNT(DISTINCT SUPPLIER_ID || '|' || PART_ID)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST;

-- ---------------------------------------------------------------------------
-- 3. No NULL primary key columns
-- ---------------------------------------------------------------------------
SELECT
    'no_null_pk' AS check_name,
    SUM(CASE WHEN SUPPLIER_ID IS NULL OR PART_ID IS NULL THEN 1 ELSE 0 END) AS null_pk_rows,
    CASE WHEN SUM(CASE WHEN SUPPLIER_ID IS NULL OR PART_ID IS NULL THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST;

-- ---------------------------------------------------------------------------
-- 4. No negative landed costs
-- ---------------------------------------------------------------------------
SELECT
    'no_negative_landed_cost' AS check_name,
    SUM(CASE WHEN ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC < 0 THEN 1 ELSE 0 END) AS negative_rows,
    CASE WHEN SUM(CASE WHEN ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC < 0 THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST;

-- ---------------------------------------------------------------------------
-- 5. No negative freight or unit costs
-- ---------------------------------------------------------------------------
SELECT
    'no_negative_costs' AS check_name,
    SUM(CASE WHEN SUPPLIER_UNIT_COST < 0 OR ALLOCATED_FREIGHT_PER_UNIT < 0 OR TOTAL_ALLOCATED_FREIGHT < 0
             THEN 1 ELSE 0 END) AS negative_rows,
    CASE WHEN SUM(CASE WHEN SUPPLIER_UNIT_COST < 0 OR ALLOCATED_FREIGHT_PER_UNIT < 0 OR TOTAL_ALLOCATED_FREIGHT < 0
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST;

-- ---------------------------------------------------------------------------
-- 6. Additive consistency: landed = unit_cost + freight_per_unit
-- ---------------------------------------------------------------------------
SELECT
    'additive_consistency' AS check_name,
    SUM(CASE WHEN ABS(ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC
                    - (SUPPLIER_UNIT_COST + ALLOCATED_FREIGHT_PER_UNIT)) > 0.01
             THEN 1 ELSE 0 END) AS inconsistent_rows,
    CASE WHEN SUM(CASE WHEN ABS(ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC
                            - (SUPPLIER_UNIT_COST + ALLOCATED_FREIGHT_PER_UNIT)) > 0.01
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST;

-- ---------------------------------------------------------------------------
-- 7. Quantity-weighted freight: total_freight / total_qty = freight_per_unit
-- ---------------------------------------------------------------------------
SELECT
    'qty_weighted_freight' AS check_name,
    SUM(CASE WHEN ABS(ALLOCATED_FREIGHT_PER_UNIT
                    - ROUND(TOTAL_ALLOCATED_FREIGHT / NULLIF(TOTAL_SHIPPED_QTY, 0), 4)) > 0.01
             THEN 1 ELSE 0 END) AS inconsistent_rows,
    CASE WHEN SUM(CASE WHEN ABS(ALLOCATED_FREIGHT_PER_UNIT
                            - ROUND(TOTAL_ALLOCATED_FREIGHT / NULLIF(TOTAL_SHIPPED_QTY, 0), 4)) > 0.01
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST;

-- ---------------------------------------------------------------------------
-- 8. No M:N supplier fan-out (1 preferred supplier per part)
-- ---------------------------------------------------------------------------
SELECT
    'no_supplier_fanout' AS check_name,
    COUNT(*) AS multi_supplier_parts,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT PART_ID, COUNT(DISTINCT SUPPLIER_ID) AS supplier_count
    FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST
    GROUP BY PART_ID
    HAVING COUNT(DISTINCT SUPPLIER_ID) > 1
);

-- ---------------------------------------------------------------------------
-- 9. Coverage: shipment lines included vs excluded
-- ---------------------------------------------------------------------------
SELECT
    'coverage_pct' AS check_name,
    (SELECT SUM(SHIPMENT_LINE_COUNT) FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST)  AS included_lines,
    (SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE)               AS total_lines,
    ROUND(100.0 * (SELECT SUM(SHIPMENT_LINE_COUNT) FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST)
        / NULLIF((SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE), 0), 2) AS coverage_pct,
    CASE WHEN (SELECT SUM(SHIPMENT_LINE_COUNT) FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST) > 0
         THEN 'PASS' ELSE 'FAIL' END AS result;

-- ---------------------------------------------------------------------------
-- 10. Excluded parts: only PRT-000095 should be missing
-- ---------------------------------------------------------------------------
SELECT
    'excluded_parts' AS check_name,
    COUNT(DISTINCT sl.PART_ID) - COUNT(DISTINCT m.PART_ID) AS excluded_part_count,
    CASE WHEN COUNT(DISTINCT sl.PART_ID) - COUNT(DISTINCT m.PART_ID) = 1
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE sl
LEFT JOIN SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST m ON sl.PART_ID = m.PART_ID;

-- ---------------------------------------------------------------------------
-- 11. Shipment-level freight reconciliation (fully attributable shipments)
-- ---------------------------------------------------------------------------
WITH shipment_totals AS (
    SELECT SHIPMENT_ID, SUM(SHIPPED_QTY) AS total_qty
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE GROUP BY SHIPMENT_ID
),
covered_totals AS (
    SELECT sl.SHIPMENT_ID, SUM(sl.SHIPPED_QTY) AS covered_qty
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE sl
    JOIN SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART bsp
        ON sl.PART_ID = bsp.PART_ID AND bsp.PREFERRED_SUPPLIER_FLAG = TRUE AND bsp.ACTIVE_FLAG = TRUE
    GROUP BY sl.SHIPMENT_ID
),
fully_covered AS (
    SELECT st.SHIPMENT_ID
    FROM shipment_totals st
    JOIN covered_totals ct ON st.SHIPMENT_ID = ct.SHIPMENT_ID
    WHERE st.total_qty = ct.covered_qty
),
per_shipment AS (
    SELECT sl.SHIPMENT_ID,
        ROUND(SUM(s.SHIPPING_COST * (sl.SHIPPED_QTY / st.total_qty)), 4) AS sum_alloc,
        ROUND(MAX(s.SHIPPING_COST), 4) AS orig_cost
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE sl
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT s ON sl.SHIPMENT_ID = s.SHIPMENT_ID
    JOIN shipment_totals st ON sl.SHIPMENT_ID = st.SHIPMENT_ID
    JOIN SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART bsp
        ON sl.PART_ID = bsp.PART_ID AND bsp.PREFERRED_SUPPLIER_FLAG = TRUE AND bsp.ACTIVE_FLAG = TRUE
    WHERE sl.SHIPMENT_ID IN (SELECT SHIPMENT_ID FROM fully_covered)
    GROUP BY sl.SHIPMENT_ID
)
SELECT
    'freight_reconciliation' AS check_name,
    COUNT(*) AS fully_covered_shipments,
    SUM(CASE WHEN ABS(sum_alloc - orig_cost) > 0.01 THEN 1 ELSE 0 END) AS mismatches,
    CASE WHEN SUM(CASE WHEN ABS(sum_alloc - orig_cost) > 0.01 THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM per_shipment;

-- ---------------------------------------------------------------------------
-- 12. Min/Max bounds: min <= landed <= max
-- ---------------------------------------------------------------------------
SELECT
    'min_max_bounds' AS check_name,
    SUM(CASE WHEN MIN_LANDED_UNIT_COST > ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC
              OR MAX_LANDED_UNIT_COST < ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC
             THEN 1 ELSE 0 END) AS out_of_bounds,
    CASE WHEN SUM(CASE WHEN MIN_LANDED_UNIT_COST > ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC
                        OR MAX_LANDED_UNIT_COST < ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC
                       THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST;
