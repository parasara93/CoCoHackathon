-- =============================================================================
-- SV_CUSTOMER_IMPACT — Semantic View Definition
-- =============================================================================
-- Deployed to: SUPPLY_CHAIN_DW.GOLD.SV_CUSTOMER_IMPACT
-- Source: SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT
-- Grain: CUSTOMER_ID (200 rows)
-- Agent consumer: Customer Impact Agent
--
-- This file is the version-controlled source of truth.
-- Deploy via: snowflake_sql_execute or schemachange R__ repeatable migration.
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW SUPPLY_CHAIN_DW.GOLD.SV_CUSTOMER_IMPACT

  TABLES (
    customer_impact AS SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT
      PRIMARY KEY (CUSTOMER_ID)
      WITH SYNONYMS ('customer impact', 'customer risk', 'customer service')
      COMMENT = 'Customer-level supply-chain impact: fulfillment rates, late orders, outstanding demand, delay metrics, and impact classification. One row per customer.'
  )

  FACTS (
    customer_impact.total_order_count AS TOTAL_ORDER_COUNT
      COMMENT = 'Total orders placed by this customer',
    customer_impact.open_order_count AS OPEN_ORDER_COUNT
      COMMENT = 'Orders with at least one active (non-delivered, non-cancelled) line',
    customer_impact.fulfilled_order_count AS FULFILLED_ORDER_COUNT
      COMMENT = 'Fully fulfilled orders',
    customer_impact.partially_fulfilled_order_count AS PARTIALLY_FULFILLED_ORDER_COUNT
      COMMENT = 'Partially fulfilled orders',
    customer_impact.unfulfilled_order_count AS UNFULFILLED_ORDER_COUNT
      COMMENT = 'Orders with no shipments',
    customer_impact.cancelled_order_count AS CANCELLED_ORDER_COUNT
      COMMENT = 'Fully cancelled orders',
    customer_impact.current_late_order_count AS CURRENT_LATE_ORDER_COUNT
      COMMENT = 'Orders currently past due with unfulfilled demand',
    customer_impact.delivered_late_order_count AS DELIVERED_LATE_ORDER_COUNT
      COMMENT = 'Orders delivered after requested date',
    customer_impact.total_late_order_count AS TOTAL_LATE_ORDER_COUNT
      COMMENT = 'Orders with any lateness signal',
    customer_impact.active_ordered_qty AS ACTIVE_ORDERED_QTY
      COMMENT = 'Total quantity ordered (non-cancelled)',
    customer_impact.active_shipped_qty AS ACTIVE_SHIPPED_QTY
      COMMENT = 'Total quantity shipped',
    customer_impact.outstanding_qty AS OUTSTANDING_QTY
      COMMENT = 'Total quantity still owed to this customer',
    customer_impact.fulfillment_pct AS FULFILLMENT_PCT
      COMMENT = 'Customer-level shipped-to-ordered ratio (0-100)',
    customer_impact.active_order_value AS ACTIVE_ORDER_VALUE
      COMMENT = 'Dollar value of active orders',
    customer_impact.outstanding_value AS OUTSTANDING_VALUE
      COMMENT = 'Dollar value of outstanding (unfulfilled) orders',
    customer_impact.late_affected_order_value AS LATE_AFFECTED_ORDER_VALUE
      COMMENT = 'Dollar value of currently-late order lines',
    customer_impact.overdue_outstanding_value AS OVERDUE_OUTSTANDING_VALUE
      COMMENT = 'Dollar value of past-due outstanding demand',
    customer_impact.total_shipment_count AS TOTAL_SHIPMENT_COUNT
      COMMENT = 'Total shipments serving this customer',
    customer_impact.late_shipment_count AS LATE_SHIPMENT_COUNT
      COMMENT = 'Late shipments serving this customer',
    customer_impact.avg_order_delay_days AS AVG_ORDER_DELAY_DAYS
      COMMENT = 'Average delay in days across late orders',
    customer_impact.max_order_delay_days AS MAX_ORDER_DELAY_DAYS
      COMMENT = 'Maximum delay in days for worst-case order',
    customer_impact.avg_shipment_delay_hours AS AVG_SHIPMENT_DELAY_HOURS
      COMMENT = 'Average shipment delay in hours',
    customer_impact.max_shipment_delay_hours AS MAX_SHIPMENT_DELAY_HOURS
      COMMENT = 'Maximum shipment delay in hours'
  )

  DIMENSIONS (
    customer_impact.customer_id AS CUSTOMER_ID
      COMMENT = 'Unique customer identifier',
    customer_impact.customer_name AS CUSTOMER_NAME
      WITH SYNONYMS = ('customer', 'client')
      COMMENT = 'Customer name',
    customer_impact.customer_segment AS CUSTOMER_SEGMENT
      COMMENT = 'Customer market segment',
    customer_impact.is_impacted AS IS_IMPACTED
      WITH SYNONYMS = ('impacted', 'affected customer')
      COMMENT = 'TRUE when customer has any late orders, partial fulfillment, unfulfilled orders, or late shipments',
    customer_impact.has_current_late_order AS HAS_CURRENT_LATE_ORDER
      COMMENT = 'TRUE when customer has currently overdue orders',
    customer_impact.has_delivered_late_order AS HAS_DELIVERED_LATE_ORDER
      COMMENT = 'TRUE when customer has orders delivered late',
    customer_impact.has_late_order AS HAS_LATE_ORDER
      COMMENT = 'TRUE when customer has any late order (current or delivered)',
    customer_impact.has_partial_fulfillment AS HAS_PARTIAL_FULFILLMENT
      COMMENT = 'TRUE when customer has partially fulfilled orders',
    customer_impact.has_unfulfilled_order AS HAS_UNFULFILLED_ORDER
      COMMENT = 'TRUE when customer has orders with no shipments',
    customer_impact.has_delayed_shipment AS HAS_DELAYED_SHIPMENT
      COMMENT = 'TRUE when at least one shipment to this customer was late',
    customer_impact.analysis_as_of_date AS ANALYSIS_AS_OF_DATE
      COMMENT = 'Deterministic analysis date'
  )

  METRICS (
    customer_impact.total_customer_count AS COUNT(CUSTOMER_ID)
      COMMENT = 'Total number of customers',
    customer_impact.impacted_customer_count AS SUM(CASE WHEN IS_IMPACTED THEN 1 ELSE 0 END)
      COMMENT = 'Number of impacted customers',
    customer_impact.avg_customer_fulfillment_pct AS AVG(FULFILLMENT_PCT)
      COMMENT = 'Customer grain: average fulfillment percentage across customers',
    customer_impact.total_customer_outstanding_value AS SUM(OUTSTANDING_VALUE)
      COMMENT = 'Customer grain: total outstanding value across all customers',
    customer_impact.total_overdue_value AS SUM(OVERDUE_OUTSTANDING_VALUE)
      COMMENT = 'Total past-due outstanding value',
    customer_impact.avg_max_delay_days AS AVG(MAX_ORDER_DELAY_DAYS)
      COMMENT = 'Average of per-customer maximum delay days',
    customer_impact.total_late_orders AS SUM(TOTAL_LATE_ORDER_COUNT)
      COMMENT = 'Total late orders across all customers'
  )

  COMMENT = 'Customer Impact semantic view for the Resilient Supply Chain Control Tower. Provides customer-level fulfillment rates, lateness signals, outstanding demand, and impact classification.'

  AI_SQL_GENERATION 'This semantic view has one row per customer. IS_IMPACTED means the customer has at least one late order, partial fulfillment, unfulfilled order, or late shipment. FULFILLMENT_PCT ranges 0-100. Outstanding value is the dollar amount the customer is still owed. When asked about most impacted customers, order by outstanding_value DESC or total_late_order_count DESC.'

  AI_VERIFIED_QUERIES (
    most_impacted_customers AS (
      QUESTION 'Which customers are most impacted by supply chain disruptions?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT customer_id, customer_name, customer_segment, total_order_count, total_late_order_count, partially_fulfilled_order_count + unfulfilled_order_count AS impacted_orders, outstanding_qty, outstanding_value, fulfillment_pct, avg_order_delay_days, max_order_delay_days FROM SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT WHERE is_impacted = TRUE ORDER BY outstanding_value DESC LIMIT 20'
    ),
    total_overdue_exposure AS (
      QUESTION 'What is the total overdue outstanding value across all impacted customers?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT COUNT(*) AS impacted_customers, SUM(overdue_outstanding_value) AS total_overdue_value, SUM(outstanding_value) AS total_customer_outstanding_value FROM SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT WHERE is_impacted = TRUE'
    ),
    worst_segment AS (
      QUESTION 'Which customer segment has the worst fulfillment rate?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT customer_segment, COUNT(*) AS customer_count, ROUND(AVG(fulfillment_pct), 2) AS avg_fulfillment_pct, SUM(total_late_order_count) AS total_late_orders, SUM(outstanding_value) AS total_customer_outstanding_value FROM SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT GROUP BY customer_segment ORDER BY avg_fulfillment_pct ASC'
    ),
    customers_with_worst_delays AS (
      QUESTION 'Which customers have the longest delays?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT customer_id, customer_name, max_order_delay_days, avg_order_delay_days, total_late_order_count, outstanding_value, fulfillment_pct FROM SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT WHERE max_order_delay_days IS NOT NULL ORDER BY max_order_delay_days DESC LIMIT 20'
    ),
    impact_summary AS (
      QUESTION 'How many customers are impacted and how many are not?'
      VERIFIED_AT 1728000000
      ONBOARDING_QUESTION FALSE
      VERIFIED_BY '(STEWARD = supply_chain_team)'
      SQL 'SELECT is_impacted, COUNT(*) AS customer_count, ROUND(AVG(fulfillment_pct), 2) AS avg_fulfillment_pct, SUM(outstanding_value) AS total_customer_outstanding_value FROM SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT GROUP BY is_impacted ORDER BY is_impacted DESC'
    )
  );
