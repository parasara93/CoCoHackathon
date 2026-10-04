-- =============================================================================
-- SV_SUPPLIER_RISK — Semantic View Definition
-- =============================================================================
-- Deployed to: SUPPLY_CHAIN_DW.GOLD.SV_SUPPLIER_RISK
-- Source: SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK
-- Grain: SUPPLIER_ID (20 rows)
-- Agent consumer: Supplier Risk Agent
--
-- This file is the version-controlled source of truth.
-- Deploy via: snowflake_sql_execute or schemachange R__ repeatable migration.
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW SUPPLY_CHAIN_DW.GOLD.SV_SUPPLIER_RISK

  TABLES (
    supplier_risk AS SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK
      PRIMARY KEY (SUPPLIER_ID)
      WITH SYNONYMS ('supplier risk', 'supplier performance', 'supplier exposure')
      COMMENT = 'Supplier-level risk profile: performance trends, downstream exposure, and risk classification. One row per supplier.'
  )

  FACTS (
    supplier_risk.risk_score_change AS RISK_SCORE_CHANGE
      COMMENT = 'Change in risk score from earliest to latest measurement (positive = worsening)',
    supplier_risk.on_time_delivery_pct_change AS ON_TIME_DELIVERY_PCT_CHANGE
      COMMENT = 'Change in on-time delivery percentage (negative = worsening)',
    supplier_risk.quality_score_change AS QUALITY_SCORE_CHANGE
      COMMENT = 'Change in quality score (negative = worsening)',
    supplier_risk.lead_time_change_days AS LEAD_TIME_CHANGE_DAYS
      COMMENT = 'Change in average lead time in days (positive = slower)',
    supplier_risk.latest_fill_rate_pct AS LATEST_FILL_RATE_PCT
      COMMENT = 'Most recent fill rate percentage',
    supplier_risk.latest_risk_score AS LATEST_RISK_SCORE
      COMMENT = 'Most recent risk score (0-1 scale, higher = more risky)',
    supplier_risk.earliest_risk_score AS EARLIEST_RISK_SCORE
      COMMENT = 'Earliest recorded risk score for trend comparison',
    supplier_risk.latest_on_time_delivery_pct AS LATEST_ON_TIME_DELIVERY_PCT
      COMMENT = 'Most recent on-time delivery percentage',
    supplier_risk.earliest_on_time_delivery_pct AS EARLIEST_ON_TIME_DELIVERY_PCT
      COMMENT = 'Earliest on-time delivery percentage for trend comparison',
    supplier_risk.low_inventory_exposure_pct AS LOW_INVENTORY_EXPOSURE_PCT
      COMMENT = 'Percentage of exposed inventory positions below safety stock or reorder point',
    supplier_risk.outstanding_exposure_pct AS OUTSTANDING_EXPOSURE_PCT
      COMMENT = 'Percentage of active exposed order value that remains outstanding',
    supplier_risk.active_exposed_outstanding_value AS ACTIVE_EXPOSED_OUTSTANDING_VALUE
      COMMENT = 'Dollar value of active outstanding orders for parts from this supplier',
    supplier_risk.exposed_late_order_line_count AS EXPOSED_LATE_ORDER_LINE_COUNT
      COMMENT = 'Number of order lines past due involving parts from this supplier',
    supplier_risk.late_shipment_pct AS LATE_SHIPMENT_PCT
      COMMENT = 'Percentage of shipments carrying this suppliers parts that were late',
    supplier_risk.supplied_part_count AS SUPPLIED_PART_COUNT
      COMMENT = 'Number of distinct parts actively supplied',
    supplier_risk.exposed_plant_count AS EXPOSED_PLANT_COUNT
      COMMENT = 'Number of plants with inventory exposure to this supplier',
    supplier_risk.exposed_shipment_count AS EXPOSED_SHIPMENT_COUNT
      COMMENT = 'Total shipments that carried parts from this supplier',
    supplier_risk.late_shipment_count AS LATE_SHIPMENT_COUNT
      COMMENT = 'Number of late shipments carrying this suppliers parts',
    supplier_risk.exposed_order_count AS EXPOSED_ORDER_COUNT
      COMMENT = 'Number of orders containing parts from this supplier',
    supplier_risk.measurement_period_count AS MEASUREMENT_PERIOD_COUNT
      COMMENT = 'Number of performance measurement periods available'
  )

  DIMENSIONS (
    supplier_risk.supplier_id AS SUPPLIER_ID
      COMMENT = 'Unique supplier identifier (e.g. SUP-000016)',
    supplier_risk.supplier_name AS SUPPLIER_NAME
      WITH SYNONYMS = ('supplier', 'vendor')
      COMMENT = 'Human-readable supplier name',
    supplier_risk.supplier_tier AS SUPPLIER_TIER
      COMMENT = 'Supplier classification tier'
      SAMPLE_VALUES ('TIER_1', 'TIER_2', 'TIER_3')
      IS_ENUM,
    supplier_risk.supplier_status AS SUPPLIER_STATUS
      COMMENT = 'Current operational status'
      SAMPLE_VALUES ('ACTIVE')
      IS_ENUM,
    supplier_risk.is_supplier_at_risk AS IS_SUPPLIER_AT_RISK
      WITH SYNONYMS = ('at risk', 'risky supplier')
      COMMENT = 'TRUE when supplier has both performance deterioration AND downstream exposure',
    supplier_risk.has_supplier_performance_deterioration AS HAS_SUPPLIER_PERFORMANCE_DETERIORATION
      COMMENT = 'TRUE when any performance metric has deteriorated',
    supplier_risk.has_downstream_exposure AS HAS_DOWNSTREAM_EXPOSURE
      COMMENT = 'TRUE when supplier has late shipments, outstanding orders, or low inventory',
    supplier_risk.has_otd_deterioration AS HAS_OTD_DETERIORATION
      COMMENT = 'TRUE when on-time delivery declined',
    supplier_risk.has_quality_deterioration AS HAS_QUALITY_DETERIORATION
      COMMENT = 'TRUE when quality score declined',
    supplier_risk.has_lead_time_deterioration AS HAS_LEAD_TIME_DETERIORATION
      COMMENT = 'TRUE when average lead time increased',
    supplier_risk.has_risk_score_increase AS HAS_RISK_SCORE_INCREASE
      COMMENT = 'TRUE when risk score increased',
    supplier_risk.has_late_shipment_exposure AS HAS_LATE_SHIPMENT_EXPOSURE
      COMMENT = 'TRUE when at least one late shipment carrying this suppliers parts',
    supplier_risk.has_outstanding_order_exposure AS HAS_OUTSTANDING_ORDER_EXPOSURE
      COMMENT = 'TRUE when outstanding order value exists for this suppliers parts',
    supplier_risk.has_low_inventory_exposure AS HAS_LOW_INVENTORY_EXPOSURE
      COMMENT = 'TRUE when inventory positions for this suppliers parts are below threshold',
    supplier_risk.analysis_as_of_date AS ANALYSIS_AS_OF_DATE
      COMMENT = 'Deterministic analysis date derived from the dataset',
    supplier_risk.latest_measurement_date AS LATEST_MEASUREMENT_DATE
      COMMENT = 'Date of most recent supplier performance measurement'
  )

  METRICS (
    supplier_risk.total_supplier_count AS COUNT(SUPPLIER_ID)
      COMMENT = 'Total number of suppliers',
    supplier_risk.at_risk_supplier_count AS COUNT(CASE WHEN IS_SUPPLIER_AT_RISK THEN SUPPLIER_ID END)
      COMMENT = 'Number of suppliers flagged as at-risk',
    supplier_risk.avg_risk_score_change AS AVG(RISK_SCORE_CHANGE)
      COMMENT = 'Average risk score change across suppliers',
    supplier_risk.avg_otd_change AS AVG(ON_TIME_DELIVERY_PCT_CHANGE)
      COMMENT = 'Average on-time delivery change across suppliers',
    supplier_risk.total_exposed_outstanding_value AS SUM(ACTIVE_EXPOSED_OUTSTANDING_VALUE)
      COMMENT = 'Total outstanding order value exposed across all suppliers',
    supplier_risk.total_exposed_late_lines AS SUM(EXPOSED_LATE_ORDER_LINE_COUNT)
      COMMENT = 'Total late order lines across all suppliers',
    supplier_risk.avg_low_inventory_exposure_pct AS AVG(LOW_INVENTORY_EXPOSURE_PCT)
      COMMENT = 'Average low-inventory exposure percentage across suppliers',
    supplier_risk.avg_supplier_late_shipment_pct AS AVG(LATE_SHIPMENT_PCT)
      COMMENT = 'Supplier grain: average late shipment percentage across suppliers'
  )

  COMMENT = 'Supplier Risk semantic view for the Resilient Supply Chain Control Tower. Provides supplier-level risk profiles including performance trends, downstream exposure, and risk classification.'

  AI_SQL_GENERATION 'This semantic view has one row per supplier. All measures are at supplier grain. When asked about a specific supplier, filter by supplier_id. Risk score ranges 0-1 (higher = more risky). Negative OTD/quality changes mean deterioration. Positive lead time/risk score changes mean deterioration. IS_SUPPLIER_AT_RISK requires BOTH performance deterioration AND downstream exposure.'

  AI_VERIFIED_QUERIES (
    at_risk_suppliers AS (
      QUESTION 'Which suppliers are at risk and why?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT supplier_id, supplier_name, supplier_tier, risk_score_change, on_time_delivery_pct_change, latest_fill_rate_pct, lead_time_change_days, low_inventory_exposure_pct, outstanding_exposure_pct, late_shipment_pct, has_otd_deterioration, has_quality_deterioration, has_lead_time_deterioration, has_late_shipment_exposure, has_outstanding_order_exposure, has_low_inventory_exposure FROM SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK WHERE is_supplier_at_risk = TRUE ORDER BY risk_score_change DESC'
    ),
    sup_000016_profile AS (
      QUESTION 'What is the risk profile of SUP-000016?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT supplier_id, supplier_name, supplier_tier, supplier_status, latest_risk_score, earliest_risk_score, risk_score_change, latest_on_time_delivery_pct, earliest_on_time_delivery_pct, on_time_delivery_pct_change, latest_fill_rate_pct, lead_time_change_days, supplied_part_count, exposed_plant_count, low_inventory_exposure_pct, outstanding_exposure_pct, active_exposed_outstanding_value, exposed_late_order_line_count, late_shipment_pct, is_supplier_at_risk FROM SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK WHERE supplier_id = ''SUP-000016'''
    ),
    worst_otd_decline AS (
      QUESTION 'Which suppliers have the largest on-time-delivery deterioration?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT supplier_id, supplier_name, supplier_tier, earliest_on_time_delivery_pct, latest_on_time_delivery_pct, on_time_delivery_pct_change, is_supplier_at_risk FROM SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK WHERE on_time_delivery_pct_change < 0 ORDER BY on_time_delivery_pct_change ASC'
    ),
    highest_outstanding_exposure AS (
      QUESTION 'Which suppliers have the highest downstream outstanding exposure?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT supplier_id, supplier_name, active_exposed_outstanding_value, outstanding_exposure_pct, exposed_order_count, exposed_late_order_line_count, is_supplier_at_risk FROM SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK WHERE active_exposed_outstanding_value > 0 ORDER BY active_exposed_outstanding_value DESC'
    ),
    deterioration_with_inventory_pressure AS (
      QUESTION 'Which suppliers combine deteriorating performance with inventory pressure?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT supplier_id, supplier_name, risk_score_change, on_time_delivery_pct_change, lead_time_change_days, low_inventory_exposure_pct, outstanding_exposure_pct, is_supplier_at_risk FROM SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK WHERE has_supplier_performance_deterioration = TRUE AND has_low_inventory_exposure = TRUE ORDER BY low_inventory_exposure_pct DESC'
    )
  );
