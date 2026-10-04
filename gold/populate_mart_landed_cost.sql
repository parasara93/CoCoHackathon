-- =============================================================================
-- Populate MART_LANDED_COST
-- =============================================================================
-- Estimated landed unit cost per supplier-part using quantity-based freight
-- allocation and preferred-supplier attribution.
--
-- Freight allocation rule:
--   For each shipment line:
--     allocated_freight = SHIPPING_COST * (SHIPPED_QTY / total_shipped_qty_in_shipment)
--   At SUPPLIER_ID + PART_ID grain (quantity-weighted):
--     ALLOCATED_FREIGHT_PER_UNIT = SUM(allocated_freight) / SUM(SHIPPED_QTY)
--   Final metric:
--     ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC = SUPPLIER_UNIT_COST + ALLOCATED_FREIGHT_PER_UNIT
--
-- Supplier attribution: PREFERRED_SUPPLIER_FLAG = TRUE AND ACTIVE_FLAG = TRUE
--   from SILVER.BRIDGE_SUPPLIER_PART (exactly 1 preferred supplier per part).
--
-- Exclusions: Parts without a preferred supplier (PRT-000095: 3 active suppliers,
--   none preferred; 39 of 6886 shipment lines = 0.6%).
--
-- Allocation basis: QUANTITY (not weight, volume, or value).
-- This is an ESTIMATED metric, not accounting-grade landed cost.
--
-- Idempotent: TRUNCATE + INSERT.
-- Prerequisites: SILVER.FACT_SHIPMENT, SILVER.FACT_SHIPMENT_LINE,
--   SILVER.BRIDGE_SUPPLIER_PART populated.
-- =============================================================================

TRUNCATE TABLE SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST;

INSERT INTO SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST (
    SUPPLIER_ID,
    PART_ID,
    ANALYSIS_DATE,
    SHIPMENT_LINE_COUNT,
    SHIPMENT_COUNT,
    TOTAL_SHIPPED_QTY,
    SUPPLIER_UNIT_COST,
    TOTAL_ALLOCATED_FREIGHT,
    ALLOCATED_FREIGHT_PER_UNIT,
    ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC,
    MIN_LANDED_UNIT_COST,
    MAX_LANDED_UNIT_COST
)

WITH shipment_totals AS (
    -- Denominator for quantity-proportional freight allocation per shipment
    SELECT
        SHIPMENT_ID,
        SUM(SHIPPED_QTY) AS total_shipment_qty
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE
    GROUP BY SHIPMENT_ID
),

line_freight AS (
    -- Per-line freight allocation: SHIPPING_COST * (line_qty / shipment_qty)
    SELECT
        sl.SHIPMENT_LINE_ID,
        sl.SHIPMENT_ID,
        sl.PART_ID,
        sl.SHIPPED_QTY,
        s.SHIPPING_COST,
        st.total_shipment_qty,
        s.SHIPPING_COST * (sl.SHIPPED_QTY / st.total_shipment_qty)
            AS allocated_freight,
        -- Per-unit freight for this specific line (for min/max variability)
        s.SHIPPING_COST / st.total_shipment_qty
            AS line_freight_per_unit
    FROM SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE sl
    JOIN SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT s
        ON sl.SHIPMENT_ID = s.SHIPMENT_ID
    JOIN shipment_totals st
        ON sl.SHIPMENT_ID = st.SHIPMENT_ID
    WHERE sl.SHIPPED_QTY > 0
      AND st.total_shipment_qty > 0
),

supplier_attribution AS (
    -- Exactly one preferred supplier per part (M:N resolved to 1:1)
    SELECT SUPPLIER_ID, PART_ID, SUPPLIER_UNIT_COST
    FROM SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART
    WHERE PREFERRED_SUPPLIER_FLAG = TRUE
      AND ACTIVE_FLAG = TRUE
),

line_with_supplier AS (
    -- Join freight with supplier; compute per-line landed unit cost
    SELECT
        lf.SHIPMENT_LINE_ID,
        lf.SHIPMENT_ID,
        sa.SUPPLIER_ID,
        lf.PART_ID,
        lf.SHIPPED_QTY,
        lf.allocated_freight,
        lf.line_freight_per_unit,
        sa.SUPPLIER_UNIT_COST,
        sa.SUPPLIER_UNIT_COST + lf.line_freight_per_unit AS line_landed_unit_cost
    FROM line_freight lf
    JOIN supplier_attribution sa
        ON lf.PART_ID = sa.PART_ID
)

-- Aggregate to SUPPLIER_ID + PART_ID grain with quantity-weighted freight
SELECT
    SUPPLIER_ID,
    PART_ID,
    CURRENT_DATE()                                              AS ANALYSIS_DATE,
    COUNT(DISTINCT SHIPMENT_LINE_ID)                            AS SHIPMENT_LINE_COUNT,
    COUNT(DISTINCT SHIPMENT_ID)                                 AS SHIPMENT_COUNT,
    SUM(SHIPPED_QTY)                                            AS TOTAL_SHIPPED_QTY,
    MAX(SUPPLIER_UNIT_COST)                                     AS SUPPLIER_UNIT_COST,
    ROUND(SUM(allocated_freight), 4)                            AS TOTAL_ALLOCATED_FREIGHT,
    -- Quantity-weighted: total freight / total qty (NOT unweighted AVG)
    ROUND(SUM(allocated_freight) / SUM(SHIPPED_QTY), 4)         AS ALLOCATED_FREIGHT_PER_UNIT,
    -- Governed metric
    ROUND(MAX(SUPPLIER_UNIT_COST)
        + SUM(allocated_freight) / SUM(SHIPPED_QTY), 4)         AS ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC,
    MIN(line_landed_unit_cost)                                  AS MIN_LANDED_UNIT_COST,
    MAX(line_landed_unit_cost)                                  AS MAX_LANDED_UNIT_COST
FROM line_with_supplier
GROUP BY SUPPLIER_ID, PART_ID;
