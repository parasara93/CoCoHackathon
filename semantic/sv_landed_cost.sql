-- =============================================================================
-- SV_LANDED_COST — Semantic View Definition
-- =============================================================================
-- Deployed to: SUPPLY_CHAIN_DW.GOLD.SV_LANDED_COST
-- Source: SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST
-- Grain: SUPPLIER_ID + PART_ID (142 rows)
--
-- Estimated landed unit cost using quantity-based freight allocation
-- and preferred-supplier attribution.
-- Formula: SUPPLIER_UNIT_COST + SUM(allocated_freight) / SUM(shipped_qty)
-- Allocation basis: QUANTITY (not weight, volume, or value)
-- Supplier attribution: preferred supplier per part (BRIDGE_SUPPLIER_PART)
-- Parts without preferred supplier excluded (PRT-000095)
-- Coverage: 99.38% of shipment lines (6,847 of 6,890)
-- This is an ESTIMATED metric, not accounting-grade landed cost.
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW SUPPLY_CHAIN_DW.GOLD.SV_LANDED_COST

  TABLES (
    landed_cost AS SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST
      PRIMARY KEY (SUPPLIER_ID, PART_ID)
      WITH SYNONYMS ('landed cost', 'total cost per unit', 'freight-inclusive cost')
      COMMENT = 'Estimated landed unit cost per supplier-part using quantity-based freight allocation and preferred-supplier attribution. One row per supplier+part. Allocation basis is quantity (not weight, volume, or value). Parts without a preferred supplier are excluded. This is an estimated metric, not accounting-grade landed cost.'
  )

  FACTS (
    landed_cost.supplier_unit_cost AS SUPPLIER_UNIT_COST
      COMMENT = 'Supplier unit cost from the preferred supplier-part relationship (BRIDGE_SUPPLIER_PART where PREFERRED_SUPPLIER_FLAG = TRUE)',
    landed_cost.allocated_freight_per_unit AS ALLOCATED_FREIGHT_PER_UNIT
      COMMENT = 'Quantity-weighted average freight cost per unit: SUM(allocated_freight) / SUM(shipped_qty) across all shipments carrying this part. Allocation: SHIPPING_COST * (line_qty / shipment_total_qty).',
    landed_cost.estimated_landed_unit_cost_qty_alloc AS ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC
      COMMENT = 'Estimated landed unit cost using quantity-based freight allocation and preferred-supplier attribution. Formula: SUPPLIER_UNIT_COST + SUM(allocated_freight) / SUM(shipped_qty). This is an estimate, not accounting-grade landed cost.',
    landed_cost.min_landed_unit_cost AS MIN_LANDED_UNIT_COST
      COMMENT = 'Minimum per-shipment landed unit cost observed for this supplier-part',
    landed_cost.max_landed_unit_cost AS MAX_LANDED_UNIT_COST
      COMMENT = 'Maximum per-shipment landed unit cost observed for this supplier-part',
    landed_cost.total_shipped_qty AS TOTAL_SHIPPED_QTY
      COMMENT = 'Total units shipped for this supplier-part across all shipments',
    landed_cost.total_allocated_freight AS TOTAL_ALLOCATED_FREIGHT
      COMMENT = 'Total quantity-proportional freight allocated to this supplier-part across all shipments',
    landed_cost.shipment_line_count AS SHIPMENT_LINE_COUNT
      COMMENT = 'Number of shipment lines contributing to this cost estimate',
    landed_cost.shipment_count AS SHIPMENT_COUNT
      COMMENT = 'Number of distinct shipments carrying this part'
  )

  DIMENSIONS (
    landed_cost.supplier_id AS SUPPLIER_ID
      COMMENT = 'Preferred supplier for this part (from BRIDGE_SUPPLIER_PART where PREFERRED_SUPPLIER_FLAG = TRUE)',
    landed_cost.part_id AS PART_ID
      COMMENT = 'Part identifier',
    landed_cost.analysis_date AS ANALYSIS_DATE
      COMMENT = 'Date the landed cost estimate was computed'
  )

  METRICS (
    landed_cost.avg_landed_cost AS AVG(ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC)
      COMMENT = 'Average estimated landed unit cost across all supplier-part positions',
    landed_cost.total_freight AS SUM(TOTAL_ALLOCATED_FREIGHT)
      COMMENT = 'Total freight allocated across all supplier-part positions',
    landed_cost.avg_freight_share AS AVG(ALLOCATED_FREIGHT_PER_UNIT / NULLIF(ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC, 0) * 100)
      COMMENT = 'Average freight share as percentage of landed cost'
  )

  COMMENT = 'Landed Cost semantic view for the Resilient Supply Chain Control Tower. Estimated landed unit cost per supplier-part using quantity-based freight allocation and preferred-supplier attribution. Formula: SUPPLIER_UNIT_COST + SUM(allocated_freight) / SUM(shipped_qty). Allocation basis: shipment freight distributed proportionally by shipped quantity. Parts without a preferred supplier excluded (1 of 143 parts, 99.38% line coverage). This is an estimated metric, not accounting-grade landed cost.'

  AI_SQL_GENERATION 'This semantic view has one row per supplier-part combination (composite key: SUPPLIER_ID + PART_ID, 142 rows). ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC = SUPPLIER_UNIT_COST + ALLOCATED_FREIGHT_PER_UNIT, where ALLOCATED_FREIGHT_PER_UNIT is quantity-weighted: SUM(allocated_freight) / SUM(shipped_qty). Freight allocation is quantity-based. Parts without a preferred supplier are excluded. This is an estimated metric.'

  AI_VERIFIED_QUERIES (
    highest_landed_cost AS (
      QUESTION 'Which supplier-part combinations have the highest estimated landed unit cost?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT supplier_id, part_id, supplier_unit_cost, allocated_freight_per_unit, estimated_landed_unit_cost_qty_alloc, shipment_count, total_shipped_qty FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST ORDER BY estimated_landed_unit_cost_qty_alloc DESC LIMIT 20'
    ),
    freight_share AS (
      QUESTION 'Which parts have the highest freight share relative to total landed cost?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT supplier_id, part_id, supplier_unit_cost, allocated_freight_per_unit, estimated_landed_unit_cost_qty_alloc, ROUND(allocated_freight_per_unit / NULLIF(estimated_landed_unit_cost_qty_alloc, 0) * 100, 2) AS freight_pct FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST ORDER BY freight_pct DESC LIMIT 20'
    )
  );
