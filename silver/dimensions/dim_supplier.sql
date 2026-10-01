-- =============================================================================
-- DIM_SUPPLIER
-- Target: SUPPLY_CHAIN_DW.SILVER.DIM_SUPPLIER
-- Source: SUPPLY_CHAIN_RAW_DATASET.RAW.SUPPLIERS
-- Grain:  One row per supplier (SUPPLIER_ID)
-- Dedup:  N/A — SUPPLIERS is a static reference table
-- Recovered: Exact CTAS from query history (2026-09-29 23:39:47)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_SUPPLIER AS
SELECT
  SUPPLIER_ID,
  SUPPLIER_NAME,
  CITY,
  STATE,
  COUNTRY,
  SUPPLIER_TIER,
  SUPPLIER_STATUS,
  CREATED_AT
FROM SUPPLY_CHAIN_RAW_DATASET.RAW.SUPPLIERS;
