-- =============================================================================
-- FACT_ORDER_LINE
-- Target: SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE
-- Source: SUPPLY_CHAIN_RAW_DATASET.RAW.ORDER_LINES
--         SUPPLY_CHAIN_RAW_DATASET.RAW.ORDERS
-- Grain:  One row per order line (ORDER_LINE_ID)
-- Dedup:  ORDERS by ORDER_ID, ORDER_LINES by ORDER_LINE_ID
--         Both use ROW_NUMBER() ordered by LAST_UPDATED_AT DESC
-- Recovered: Exact CTAS from query history (2026-09-30 00:28:33)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE AS
WITH orders_dedup AS (
  SELECT *
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY ORDER_ID ORDER BY LAST_UPDATED_AT DESC) AS rn
    FROM SUPPLY_CHAIN_RAW_DATASET.RAW.ORDERS
  )
  WHERE rn = 1
),
order_lines_dedup AS (
  SELECT *
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY ORDER_LINE_ID ORDER BY LAST_UPDATED_AT DESC) AS rn
    FROM SUPPLY_CHAIN_RAW_DATASET.RAW.ORDER_LINES
  )
  WHERE rn = 1
)
SELECT
  ol.ORDER_LINE_ID,
  ol.ORDER_ID,
  o.CUSTOMER_ID,
  o.PLANT_ID,
  ol.PART_ID,
  o.ORDER_DATE::DATE                     AS ORDER_DATE_KEY,
  o.REQUESTED_DELIVERY_DATE              AS REQUESTED_DELIVERY_DATE_KEY,
  o.ORDER_STATUS,
  ol.LINE_STATUS,
  ol.ORDERED_QTY,
  ol.UNIT_PRICE,
  ol.LINE_AMOUNT,
  o.ORDER_TOTAL,
  ol.CREATED_AT                          AS LINE_CREATED_AT,
  ol.LAST_UPDATED_AT                     AS LINE_UPDATED_AT,
  o.LAST_UPDATED_AT                      AS ORDER_UPDATED_AT
FROM order_lines_dedup ol
JOIN orders_dedup o ON ol.ORDER_ID = o.ORDER_ID;
