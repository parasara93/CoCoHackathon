-- =============================================================================
-- FACT_SHIPMENT_LINE
-- Target: SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE
-- Source: SUPPLY_CHAIN_DW.RAW.SHIPMENT_LINES
-- Grain:  One row per shipment line (SHIPMENT_LINE_ID)
-- Dedup:  N/A — SHIPMENT_LINES has no version columns
-- Recovered: Exact CTAS from query history (2026-09-29 23:46:19)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE AS
SELECT
  SHIPMENT_LINE_ID,
  SHIPMENT_ID,
  ORDER_LINE_ID,
  PART_ID,
  SHIPPED_QTY,
  CREATED_AT
FROM SUPPLY_CHAIN_DW.RAW.SHIPMENT_LINES;
