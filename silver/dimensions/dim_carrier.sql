-- =============================================================================
-- DIM_CARRIER
-- Target: SUPPLY_CHAIN_DW.SILVER.DIM_CARRIER
-- Source: SUPPLY_CHAIN_DW.RAW.CARRIERS
-- Grain:  One row per carrier (CARRIER_ID)
-- Dedup:  N/A — CARRIERS is a static reference table
-- Recovered: Exact CTAS from query history (2026-09-29 23:40:01)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_CARRIER AS
SELECT
  CARRIER_ID,
  CARRIER_NAME,
  CARRIER_TYPE,
  SERVICE_LEVEL,
  BASE_COST_PER_KM,
  ACTIVE_FLAG,
  CREATED_AT
FROM SUPPLY_CHAIN_DW.RAW.CARRIERS;
