-- =============================================================================
-- SV_ORDER_FULFILLMENT — Semantic View Definition
-- =============================================================================
-- Deployed to: SUPPLY_CHAIN_DW.GOLD.SV_ORDER_FULFILLMENT
-- Source: SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT
-- Grain: ORDER_ID (4,934 rows)
-- Agent consumer: Order Fulfillment Agent
--
-- This file is the version-controlled source of truth.
-- Deploy via: snowflake_sql_execute or schemachange R__ repeatable migration.
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW SUPPLY_CHAIN_DW.GOLD.SV_ORDER_FULFILLMENT

  TABLES (
    order_fulfillment AS SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT
      PRIMARY KEY (ORDER_ID)
      WITH SYNONYMS ('order fulfillment', 'orders', 'fulfillment')
      COMMENT = 'Order-level fulfillment performance: fill state, quantities, values, lateness, and shipment metrics. One row per order.'
  )

  FACTS (
    order_fulfillment.total_order_line_count AS TOTAL_ORDER_LINE_COUNT
      COMMENT = 'Total order lines in this order',
    order_fulfillment.cancelled_line_count AS CANCELLED_LINE_COUNT
      COMMENT = 'Number of cancelled lines',
    order_fulfillment.active_line_count AS ACTIVE_LINE_COUNT
      COMMENT = 'Number of active (non-cancelled) lines',
    order_fulfillment.ordered_qty AS ORDERED_QTY
      COMMENT = 'Total quantity ordered across all lines',
    order_fulfillment.active_ordered_qty AS ACTIVE_ORDERED_QTY
      COMMENT = 'Ordered quantity excluding cancelled lines',
    order_fulfillment.raw_shipped_qty AS RAW_SHIPPED_QTY
      COMMENT = 'Total shipped quantity (may exceed ordered for over-shipments)',
    order_fulfillment.effective_shipped_qty AS EFFECTIVE_SHIPPED_QTY
      COMMENT = 'Shipped quantity capped at ordered quantity per line',
    order_fulfillment.outstanding_qty AS OUTSTANDING_QTY
      COMMENT = 'Quantity still owed (active ordered minus effective shipped)',
    order_fulfillment.over_shipped_qty AS OVER_SHIPPED_QTY
      COMMENT = 'Quantity shipped beyond what was ordered',
    order_fulfillment.fulfillment_pct AS FULFILLMENT_PCT
      COMMENT = 'Percentage of active ordered quantity that has been shipped (0-100)',
    order_fulfillment.order_value AS ORDER_VALUE
      COMMENT = 'Total dollar value of the order',
    order_fulfillment.active_order_value AS ACTIVE_ORDER_VALUE
      COMMENT = 'Dollar value of active (non-delivered, non-cancelled) lines',
    order_fulfillment.outstanding_value AS OUTSTANDING_VALUE
      COMMENT = 'Dollar value of outstanding (unfulfilled) quantity',
    order_fulfillment.shipment_count AS SHIPMENT_COUNT
      COMMENT = 'Number of distinct shipments serving this order',
    order_fulfillment.late_shipment_count AS LATE_SHIPMENT_COUNT
      COMMENT = 'Number of late shipments for this order',
    order_fulfillment.current_delay_days AS CURRENT_DELAY_DAYS
      COMMENT = 'Days past due for currently-late orders (NULL if not late)',
    order_fulfillment.max_delivered_delay_days AS MAX_DELIVERED_DELAY_DAYS
      COMMENT = 'Maximum delivered-late delay in days'
  )

  DIMENSIONS (
    order_fulfillment.order_id AS ORDER_ID
      COMMENT = 'Unique order identifier',
    order_fulfillment.customer_id AS CUSTOMER_ID
      COMMENT = 'Customer who placed the order',
    order_fulfillment.customer_name AS CUSTOMER_NAME
      WITH SYNONYMS = ('customer')
      COMMENT = 'Customer name',
    order_fulfillment.customer_segment AS CUSTOMER_SEGMENT
      COMMENT = 'Customer market segment',
    order_fulfillment.plant_id AS PLANT_ID
      COMMENT = 'Plant assigned to fulfill this order',
    order_fulfillment.plant_name AS PLANT_NAME
      WITH SYNONYMS = ('plant', 'factory')
      COMMENT = 'Plant name',
    order_fulfillment.order_date AS ORDER_DATE
      COMMENT = 'Date the order was placed',
    order_fulfillment.requested_delivery_date AS REQUESTED_DELIVERY_DATE
      COMMENT = 'Requested delivery date',
    order_fulfillment.fulfillment_state AS FULFILLMENT_STATE
      COMMENT = 'Order fulfillment classification'
      SAMPLE_VALUES ('FULFILLED', 'PARTIALLY_FULFILLED', 'UNFULFILLED', 'CANCELLED')
      IS_ENUM,
    order_fulfillment.is_fulfilled AS IS_FULFILLED
      COMMENT = 'TRUE when order is fully fulfilled',
    order_fulfillment.is_partially_fulfilled AS IS_PARTIALLY_FULFILLED
      COMMENT = 'TRUE when order is partially fulfilled',
    order_fulfillment.is_unfulfilled AS IS_UNFULFILLED
      COMMENT = 'TRUE when order has no shipments',
    order_fulfillment.is_cancelled AS IS_CANCELLED
      COMMENT = 'TRUE when all order lines are cancelled',
    order_fulfillment.is_current_late AS IS_CURRENT_LATE
      WITH SYNONYMS = ('currently late', 'overdue')
      COMMENT = 'TRUE when order has unfulfilled demand past requested delivery date (active overdue right now)',
    order_fulfillment.is_delivered_late AS IS_DELIVERED_LATE
      COMMENT = 'TRUE when order was delivered but after the requested date (historical lateness)',
    order_fulfillment.is_late AS IS_LATE
      WITH SYNONYMS = ('late', 'delayed order')
      COMMENT = 'TRUE when order has any lateness signal: currently late OR was delivered late (union of IS_CURRENT_LATE and IS_DELIVERED_LATE)',
    order_fulfillment.has_delayed_shipment AS HAS_DELAYED_SHIPMENT
      COMMENT = 'TRUE when at least one shipment was late',
    order_fulfillment.has_over_shipment AS HAS_OVER_SHIPMENT
      COMMENT = 'TRUE when shipped quantity exceeds ordered',
    order_fulfillment.analysis_as_of_date AS ANALYSIS_AS_OF_DATE
      COMMENT = 'Deterministic analysis date',
    order_fulfillment.last_actual_delivery_date AS LAST_ACTUAL_DELIVERY_DATE
      COMMENT = 'Most recent actual delivery date for this order'
  )

  METRICS (
    order_fulfillment.total_order_count AS COUNT(ORDER_ID)
      COMMENT = 'Total number of orders',
    order_fulfillment.late_order_count AS SUM(CASE WHEN IS_LATE THEN 1 ELSE 0 END)
      COMMENT = 'Number of late orders',
    order_fulfillment.unfulfilled_order_count AS SUM(CASE WHEN IS_UNFULFILLED THEN 1 ELSE 0 END)
      COMMENT = 'Number of unfulfilled orders',
    order_fulfillment.avg_order_fulfillment_pct AS AVG(FULFILLMENT_PCT)
      COMMENT = 'Order grain: average fulfillment percentage across orders',
    order_fulfillment.currently_late_order_count AS SUM(CASE WHEN IS_CURRENT_LATE THEN 1 ELSE 0 END)
      COMMENT = 'Number of orders currently overdue with unfulfilled demand',
    order_fulfillment.total_order_outstanding_qty AS SUM(OUTSTANDING_QTY)
      COMMENT = 'Order grain: total outstanding quantity across all orders',
    order_fulfillment.total_order_outstanding_value AS SUM(OUTSTANDING_VALUE)
      COMMENT = 'Order grain: total outstanding dollar value across all orders',
    order_fulfillment.avg_order_delay_days AS AVG(CURRENT_DELAY_DAYS)
      COMMENT = 'Average delay days for currently-late orders'
  )

  COMMENT = 'Order Fulfillment semantic view for the Resilient Supply Chain Control Tower. Provides order-level fulfillment state, quantity/value metrics, and lateness signals.'

  AI_SQL_GENERATION 'This semantic view has one row per order. Fulfillment states are FULFILLED, PARTIALLY_FULFILLED, UNFULFILLED, CANCELLED. GOVERNED METRIC DEFINITIONS: avg_order_fulfillment_pct is defined as AVG(FULFILLMENT_PCT) over ALL orders (no filter). Do NOT add WHERE clauses excluding cancelled orders when computing this metric — FULFILLMENT_PCT is already 0 for cancelled orders, so the average is correct without filtering. total_order_outstanding_value is SUM(OUTSTANDING_VALUE) over ALL orders (no filter) — cancelled orders have 0 outstanding. currently_late_order_count uses IS_CURRENT_LATE = TRUE specifically. LATENESS SEMANTICS: IS_CURRENT_LATE = order has unfulfilled demand past its requested delivery date (active overdue). IS_DELIVERED_LATE = order was delivered after the requested date (historical). IS_LATE = union of IS_CURRENT_LATE and IS_DELIVERED_LATE. When user says "currently late" or "overdue", use IS_CURRENT_LATE. FULFILLMENT_PCT ranges 0-100. When asked about plant backlog, group by plant_id.'

  AI_VERIFIED_QUERIES (
    plant_backlog AS (
      QUESTION 'Which plant has the highest order backlog?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT plant_id, plant_name, COUNT(*) AS backlog_orders, SUM(outstanding_qty) AS total_outstanding_qty, SUM(outstanding_value) AS total_outstanding_value FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT WHERE fulfillment_state IN (''UNFULFILLED'', ''PARTIALLY_FULFILLED'') GROUP BY plant_id, plant_name ORDER BY total_outstanding_value DESC'
    ),
    unfulfilled_at_plt003 AS (
      QUESTION 'Show all unfulfilled orders at PLT-000003'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT order_id, customer_id, customer_name, fulfillment_state, ordered_qty, effective_shipped_qty, outstanding_qty, outstanding_value, fulfillment_pct, current_delay_days, is_current_late FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT WHERE plant_id = ''PLT-000003'' AND fulfillment_state IN (''UNFULFILLED'', ''PARTIALLY_FULFILLED'') ORDER BY outstanding_value DESC'
    ),
    avg_fill_by_plant AS (
      QUESTION 'What is the average fulfillment rate by plant?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT plant_id, plant_name, COUNT(*) AS order_count, ROUND(AVG(fulfillment_pct), 2) AS avg_order_fulfillment_pct, SUM(CASE WHEN is_late THEN 1 ELSE 0 END) AS late_orders FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT GROUP BY plant_id, plant_name ORDER BY avg_order_fulfillment_pct ASC'
    ),
    highest_outstanding_late AS (
      QUESTION 'Which orders are currently late with the highest outstanding value?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT order_id, customer_id, customer_name, plant_id, fulfillment_state, outstanding_qty, outstanding_value, current_delay_days FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT WHERE is_current_late = TRUE ORDER BY outstanding_value DESC LIMIT 20'
    ),
    fulfillment_state_summary AS (
      QUESTION 'What is the distribution of order fulfillment states?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT fulfillment_state, COUNT(*) AS order_count, SUM(outstanding_qty) AS total_outstanding_qty, SUM(outstanding_value) AS total_outstanding_value, ROUND(AVG(fulfillment_pct), 2) AS avg_order_fulfillment_pct FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT GROUP BY fulfillment_state ORDER BY fulfillment_state'
    )
  );
