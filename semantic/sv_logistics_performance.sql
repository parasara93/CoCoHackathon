-- =============================================================================
-- SV_LOGISTICS_PERFORMANCE — Semantic View Definition
-- =============================================================================
-- Deployed to: SUPPLY_CHAIN_DW.GOLD.SV_LOGISTICS_PERFORMANCE
-- Source: SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
-- Grain: SHIPMENT_ID (2,997 rows)
-- Agent consumer: Logistics Performance Agent
--
-- This file is the version-controlled source of truth.
-- Deploy via: snowflake_sql_execute or schemachange R__ repeatable migration.
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW SUPPLY_CHAIN_DW.GOLD.SV_LOGISTICS_PERFORMANCE

  TABLES (
    logistics AS SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
      PRIMARY KEY (SHIPMENT_ID)
      WITH SYNONYMS ('logistics performance', 'shipments', 'delivery performance')
      COMMENT = 'Shipment-level logistics performance: transit times, delays, costs, disruption events, and route/carrier context. One row per shipment.'
  )

  FACTS (
    logistics.planned_transit_hours AS PLANNED_TRANSIT_HOURS
      COMMENT = 'Planned transit time in hours',
    logistics.actual_transit_hours AS ACTUAL_TRANSIT_HOURS
      COMMENT = 'Actual transit time in hours (NULL if not delivered)',
    logistics.transit_variance_hours AS TRANSIT_VARIANCE_HOURS
      COMMENT = 'Actual minus planned transit hours (positive = slower than planned)',
    logistics.departure_delay_hours AS DEPARTURE_DELAY_HOURS
      COMMENT = 'Hours between planned and actual departure (positive = late departure)',
    logistics.delivery_delay_hours AS DELIVERY_DELAY_HOURS
      COMMENT = 'Hours between planned and actual delivery (positive = late delivery)',
    logistics.shipping_cost AS SHIPPING_COST
      COMMENT = 'Cost of this shipment in dollars',
    logistics.distance_km AS DISTANCE_KM
      COMMENT = 'Route distance in kilometers',
    logistics.route_deviation_event_count AS ROUTE_DEVIATION_EVENT_COUNT
      COMMENT = 'Number of route deviation events for this shipment',
    logistics.delay_reported_event_count AS DELAY_REPORTED_EVENT_COUNT
      COMMENT = 'Number of delay-reported events for this shipment',
    logistics.distinct_order_count AS DISTINCT_ORDER_COUNT
      COMMENT = 'Number of distinct orders served by this shipment'
  )

  DIMENSIONS (
    logistics.shipment_id AS SHIPMENT_ID
      COMMENT = 'Unique shipment identifier',
    logistics.shipment_type AS SHIPMENT_TYPE
      COMMENT = 'Shipment direction'
      SAMPLE_VALUES ('INBOUND', 'OUTBOUND')
      IS_ENUM,
    logistics.shipment_status AS SHIPMENT_STATUS
      COMMENT = 'Current shipment status'
      SAMPLE_VALUES ('PLANNED', 'IN_TRANSIT', 'DELIVERED', 'DELAYED')
      IS_ENUM,
    logistics.carrier_id AS CARRIER_ID
      COMMENT = 'Carrier identifier',
    logistics.carrier_name AS CARRIER_NAME
      WITH SYNONYMS = ('carrier', 'shipper')
      COMMENT = 'Carrier name',
    logistics.carrier_type AS CARRIER_TYPE
      COMMENT = 'Type of carrier',
    logistics.service_level AS SERVICE_LEVEL
      COMMENT = 'Service level of the carrier',
    logistics.route_id AS ROUTE_ID
      COMMENT = 'Route identifier (e.g. RTE-000036)',
    logistics.origin_type AS ORIGIN_TYPE
      COMMENT = 'Type of origin (PLANT, SUPPLIER, etc.)',
    logistics.origin_id AS ORIGIN_ID
      COMMENT = 'Origin entity identifier',
    logistics.destination_type AS DESTINATION_TYPE
      COMMENT = 'Type of destination',
    logistics.destination_id AS DESTINATION_ID
      COMMENT = 'Destination entity identifier',
    logistics.route_risk_level AS ROUTE_RISK_LEVEL
      COMMENT = 'Risk classification of the route'
      SAMPLE_VALUES ('LOW', 'MEDIUM', 'HIGH')
      IS_ENUM,
    logistics.is_on_time AS IS_ON_TIME
      WITH SYNONYMS = ('on time', 'punctual')
      COMMENT = 'TRUE when shipment was delivered on or before planned delivery (NULL if not delivered)',
    logistics.analysis_as_of_date AS ANALYSIS_AS_OF_DATE
      COMMENT = 'Deterministic analysis date',
    logistics.planned_departure_at AS PLANNED_DEPARTURE_AT
      COMMENT = 'Planned departure timestamp',
    logistics.actual_departure_at AS ACTUAL_DEPARTURE_AT
      COMMENT = 'Actual departure timestamp',
    logistics.planned_delivery_at AS PLANNED_DELIVERY_AT
      COMMENT = 'Planned delivery timestamp',
    logistics.actual_delivery_at AS ACTUAL_DELIVERY_AT
      COMMENT = 'Actual delivery timestamp'
  )

  METRICS (
    logistics.total_shipment_count AS COUNT(SHIPMENT_ID)
      COMMENT = 'Total number of shipments',
    logistics.delayed_shipment_count AS SUM(CASE WHEN SHIPMENT_STATUS = 'DELAYED' THEN 1 ELSE 0 END)
      COMMENT = 'Number of delayed shipments',
    logistics.late_delivery_count AS SUM(CASE WHEN IS_ON_TIME = FALSE THEN 1 ELSE 0 END)
      COMMENT = 'Number of shipments delivered late',
    logistics.avg_delivery_delay_hours AS AVG(DELIVERY_DELAY_HOURS)
      COMMENT = 'Average delivery delay in hours',
    logistics.avg_transit_variance AS AVG(TRANSIT_VARIANCE_HOURS)
      COMMENT = 'Average transit variance in hours',
    logistics.total_shipping_cost AS SUM(SHIPPING_COST)
      COMMENT = 'Total shipping cost across all shipments',
    logistics.total_disruption_events AS SUM(DELAY_REPORTED_EVENT_COUNT) + SUM(ROUTE_DEVIATION_EVENT_COUNT)
      COMMENT = 'Total disruption events (delay reported + route deviation)'
  )

  COMMENT = 'Logistics Performance semantic view for the Resilient Supply Chain Control Tower. Provides shipment-level delivery performance, delay metrics, costs, and disruption event counts.'

  AI_SQL_GENERATION 'This semantic view has one row per shipment. IS_ON_TIME is NULL for undelivered shipments, TRUE for on-time, FALSE for late. Transit variance and delay hours are positive when the shipment is slower/later than planned. When asked about a specific route, filter by route_id. SHIPMENT_STATUS DELAYED means the shipment is known to be delayed. Route risk levels are LOW, MEDIUM, HIGH.'

  AI_VERIFIED_QUERIES (
    worst_route_delays AS (
      QUESTION 'Which routes have the highest delivery delays?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT route_id, route_risk_level, COUNT(*) AS shipment_count, ROUND(AVG(delivery_delay_hours), 1) AS avg_delay_hours, MAX(delivery_delay_hours) AS max_delay_hours, SUM(CASE WHEN is_on_time = FALSE THEN 1 ELSE 0 END) AS late_count FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE WHERE delivery_delay_hours > 0 GROUP BY route_id, route_risk_level ORDER BY avg_delay_hours DESC'
    ),
    rte036_disrupted AS (
      QUESTION 'Show all disrupted shipments on RTE-000036'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT shipment_id, shipment_status, is_on_time, planned_transit_hours, actual_transit_hours, transit_variance_hours, departure_delay_hours, delivery_delay_hours, shipping_cost, delay_reported_event_count, route_deviation_event_count FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE WHERE route_id = ''RTE-000036'' AND (shipment_status = ''DELAYED'' OR delay_reported_event_count > 0 OR route_deviation_event_count > 0) ORDER BY delivery_delay_hours DESC NULLS LAST'
    ),
    worst_carriers AS (
      QUESTION 'Which carriers have the worst on-time performance?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT carrier_id, carrier_name, COUNT(*) AS total_shipments, SUM(CASE WHEN is_on_time = FALSE THEN 1 ELSE 0 END) AS late_shipments, ROUND(100.0 * SUM(CASE WHEN is_on_time = FALSE THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN is_on_time IS NOT NULL THEN 1 ELSE 0 END), 0), 2) AS late_pct FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE GROUP BY carrier_id, carrier_name ORDER BY late_pct DESC'
    ),
    delayed_shipment_cost AS (
      QUESTION 'What is the total cost of delayed shipments?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT COUNT(*) AS delayed_shipments, SUM(shipping_cost) AS total_cost FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE WHERE shipment_status = ''DELAYED'''
    ),
    high_risk_route_summary AS (
      QUESTION 'Summarize performance on high-risk routes'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT route_id, COUNT(*) AS shipments, SUM(CASE WHEN is_on_time = FALSE THEN 1 ELSE 0 END) AS late, ROUND(AVG(transit_variance_hours), 1) AS avg_variance, SUM(delay_reported_event_count) AS delay_events, SUM(route_deviation_event_count) AS deviation_events FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE WHERE route_risk_level = ''HIGH'' GROUP BY route_id ORDER BY late DESC'
    )
  );
