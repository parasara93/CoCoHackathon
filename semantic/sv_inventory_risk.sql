-- =============================================================================
-- SV_INVENTORY_RISK — Semantic View Definition
-- =============================================================================
-- Deployed to: SUPPLY_CHAIN_DW.GOLD.SV_INVENTORY_RISK
-- Source: SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
-- Grain: PLANT_ID + PART_ID (395 rows)
-- Agent consumer: Inventory Risk Agent
--
-- This file is the version-controlled source of truth.
-- Deploy via: snowflake_sql_execute or schemachange R__ repeatable migration.
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW SUPPLY_CHAIN_DW.GOLD.SV_INVENTORY_RISK

  TABLES (
    inventory_risk AS SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
      PRIMARY KEY (PLANT_ID, PART_ID)
      WITH SYNONYMS ('inventory risk', 'stock levels', 'inventory positions')
      COMMENT = 'Plant+Part inventory position risk: stock levels, shortage signals, demand exposure, and supplier backup. One row per plant-part combination.'
  )

  FACTS (
    inventory_risk.on_hand_qty AS ON_HAND_QTY
      COMMENT = 'Total quantity physically on hand at the plant',
    inventory_risk.reserved_qty AS RESERVED_QTY
      COMMENT = 'Quantity reserved (committed to WIP or orders)',
    inventory_risk.available_qty AS AVAILABLE_QTY
      COMMENT = 'Quantity available for new demand (on_hand minus reserved)',
    inventory_risk.safety_stock AS SAFETY_STOCK
      COMMENT = 'Minimum stock threshold below which risk increases',
    inventory_risk.reorder_point AS REORDER_POINT
      COMMENT = 'Stock level that triggers a replenishment order',
    inventory_risk.below_safety_stock_qty AS BELOW_SAFETY_STOCK_QTY
      COMMENT = 'Units below safety stock threshold (0 if adequate)',
    inventory_risk.shortage_qty AS SHORTAGE_QTY
      COMMENT = 'Units below reorder point (0 if adequate)',
    inventory_risk.active_supplier_count AS ACTIVE_SUPPLIER_COUNT
      COMMENT = 'Number of active suppliers for this part (0 = single-source risk)',
    inventory_risk.active_order_count AS ACTIVE_ORDER_COUNT
      COMMENT = 'Number of active orders demanding this part at this plant',
    inventory_risk.active_ordered_qty AS ACTIVE_ORDERED_QTY
      COMMENT = 'Total quantity ordered for this part at this plant',
    inventory_risk.outstanding_order_qty AS OUTSTANDING_ORDER_QTY
      COMMENT = 'Unfulfilled demand quantity for this part at this plant',
    inventory_risk.outstanding_order_value AS OUTSTANDING_ORDER_VALUE
      COMMENT = 'Dollar value of unfulfilled demand',
    inventory_risk.order_demand_qty_90d AS ORDER_DEMAND_QTY_90D
      COMMENT = 'Total order demand quantity in the trailing 90-day window',
    inventory_risk.avg_daily_order_demand_90d AS AVG_DAILY_ORDER_DEMAND_90D
      COMMENT = 'Average daily order demand over the trailing 90-day window',
    inventory_risk.days_of_demand_coverage_90d AS DAYS_OF_DEMAND_COVERAGE_90D
      COMMENT = 'Number of days current available inventory can cover at the 90-day average demand rate (NULL when no demand)'
  )

  DIMENSIONS (
    inventory_risk.plant_id AS PLANT_ID
      COMMENT = 'Plant identifier (e.g. PLT-000003)',
    inventory_risk.part_id AS PART_ID
      COMMENT = 'Part identifier (e.g. PRT-000037)',
    inventory_risk.plant_name AS PLANT_NAME
      WITH SYNONYMS = ('plant', 'factory', 'facility')
      COMMENT = 'Human-readable plant name',
    inventory_risk.part_name AS PART_NAME
      WITH SYNONYMS = ('part', 'component')
      COMMENT = 'Human-readable part name',
    inventory_risk.part_category AS PART_CATEGORY
      COMMENT = 'Part product category',
    inventory_risk.criticality AS CRITICALITY
      COMMENT = 'Part criticality classification'
      SAMPLE_VALUES ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
      IS_ENUM,
    inventory_risk.inventory_status AS INVENTORY_STATUS
      COMMENT = 'Current inventory status'
      SAMPLE_VALUES ('ADEQUATE', 'LOW', 'CRITICAL', 'OUT_OF_STOCK')
      IS_ENUM,
    inventory_risk.needs_reorder AS NEEDS_REORDER
      WITH SYNONYMS = ('needs reorder', 'reorder needed')
      COMMENT = 'TRUE when available qty is at or below reorder point',
    inventory_risk.below_safety_stock AS BELOW_SAFETY_STOCK
      COMMENT = 'TRUE when available qty is at or below safety stock',
    inventory_risk.is_out_of_stock AS IS_OUT_OF_STOCK
      WITH SYNONYMS = ('out of stock', 'stockout')
      COMMENT = 'TRUE when available qty is zero',
    inventory_risk.analysis_as_of_date AS ANALYSIS_AS_OF_DATE
      COMMENT = 'Deterministic analysis date',
    inventory_risk.snapshot_date_key AS SNAPSHOT_DATE_KEY
      COMMENT = 'Date of the inventory snapshot'
  )

  METRICS (
    inventory_risk.total_positions AS COUNT(*)
      COMMENT = 'Total inventory positions',
    inventory_risk.out_of_stock_positions AS SUM(CASE WHEN IS_OUT_OF_STOCK THEN 1 ELSE 0 END)
      COMMENT = 'Number of out-of-stock positions',
    inventory_risk.below_safety_positions AS SUM(CASE WHEN BELOW_SAFETY_STOCK THEN 1 ELSE 0 END)
      COMMENT = 'Number of positions below safety stock',
    inventory_risk.needs_reorder_positions AS SUM(CASE WHEN NEEDS_REORDER THEN 1 ELSE 0 END)
      COMMENT = 'Number of positions needing reorder',
    inventory_risk.total_outstanding_demand AS SUM(OUTSTANDING_ORDER_QTY)
      COMMENT = 'Total unfulfilled demand quantity across positions',
    inventory_risk.total_inventory_outstanding_value AS SUM(OUTSTANDING_ORDER_VALUE)
      COMMENT = 'Inventory grain: total dollar value of unfulfilled demand',
    inventory_risk.avg_available_qty AS AVG(AVAILABLE_QTY)
      COMMENT = 'Average available quantity across positions',
    inventory_risk.total_available_qty AS SUM(AVAILABLE_QTY)
      COMMENT = 'Total available quantity across all positions',
    inventory_risk.avg_days_of_demand_coverage AS AVG(DAYS_OF_DEMAND_COVERAGE_90D)
      COMMENT = 'Average days of demand coverage across positions with demand'
  )

  COMMENT = 'Inventory Risk semantic view for the Resilient Supply Chain Control Tower. Provides plant+part inventory positions with stock levels, shortage signals, demand exposure, and supplier backup counts.'

  AI_SQL_GENERATION 'This semantic view has one row per plant-part combination (composite key: PLANT_ID + PART_ID). NEEDS_REORDER and BELOW_SAFETY_STOCK are boolean flags. Criticality values are CRITICAL, HIGH, MEDIUM, LOW. Inventory status values are ADEQUATE, LOW, CRITICAL, OUT_OF_STOCK. DAYS_OF_DEMAND_COVERAGE_90D shows how many days current available inventory can sustain at the trailing 90-day average demand rate (NULL when there is no demand). When asked about a specific part, filter by part_id. When asked about a specific plant, filter by plant_id.'

  AI_VERIFIED_QUERIES (
    below_safety_stock_parts AS (
      QUESTION 'Which parts are below safety stock and at which plants?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT plant_id, plant_name, part_id, part_name, criticality, inventory_status, available_qty, safety_stock, below_safety_stock_qty, active_supplier_count, outstanding_order_qty, days_of_demand_coverage_90d FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK WHERE below_safety_stock = TRUE ORDER BY below_safety_stock_qty DESC'
    ),
    critical_shortage_parts AS (
      QUESTION 'What is the inventory position for the critical shortage parts PRT-000037, PRT-000040, PRT-000084, PRT-000129?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT plant_id, plant_name, part_id, part_name, criticality, inventory_status, on_hand_qty, reserved_qty, available_qty, safety_stock, reorder_point, below_safety_stock_qty, shortage_qty, needs_reorder, below_safety_stock, is_out_of_stock, active_supplier_count, outstanding_order_qty, outstanding_order_value FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK WHERE part_id IN (''PRT-000037'', ''PRT-000040'', ''PRT-000084'', ''PRT-000129'') ORDER BY part_id, plant_id'
    ),
    out_of_stock_by_plant AS (
      QUESTION 'Which plant has the most out-of-stock positions?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT plant_id, plant_name, COUNT(*) AS out_of_stock_count FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK WHERE is_out_of_stock = TRUE GROUP BY plant_id, plant_name ORDER BY out_of_stock_count DESC'
    ),
    outstanding_demand_at_risk AS (
      QUESTION 'What outstanding demand is at risk from low-inventory positions?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT plant_id, plant_name, part_id, part_name, criticality, available_qty, safety_stock, outstanding_order_qty, outstanding_order_value, active_supplier_count, days_of_demand_coverage_90d FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK WHERE needs_reorder = TRUE AND outstanding_order_qty > 0 ORDER BY outstanding_order_value DESC'
    ),
    plant_003_inventory AS (
      QUESTION 'What is the inventory pressure at PLT-000003?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT plant_id, part_id, part_name, criticality, inventory_status, on_hand_qty, reserved_qty, available_qty, safety_stock, needs_reorder, below_safety_stock, is_out_of_stock, outstanding_order_qty, days_of_demand_coverage_90d FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK WHERE plant_id = ''PLT-000003'' ORDER BY available_qty ASC'
    ),
    lowest_demand_coverage AS (
      QUESTION 'Which inventory positions have the lowest days of demand coverage?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT plant_id, plant_name, part_id, part_name, criticality, available_qty, avg_daily_order_demand_90d, days_of_demand_coverage_90d, needs_reorder, below_safety_stock FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK WHERE days_of_demand_coverage_90d IS NOT NULL ORDER BY days_of_demand_coverage_90d ASC LIMIT 20'
    )
  );
