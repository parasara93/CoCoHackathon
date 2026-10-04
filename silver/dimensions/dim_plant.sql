-- =============================================================================
-- DIM_PLANT
-- Target: SUPPLY_CHAIN_DW.SILVER.DIM_PLANT
-- Source: SUPPLY_CHAIN_DW.RAW.PLANTS
-- Grain:  One row per plant (PLANT_ID)
-- Dedup:  N/A — PLANTS is a static reference table
-- Recovered: Exact CTAS from query history (2026-09-29 23:39:36)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_PLANT AS
SELECT
  PLANT_ID,
  PLANT_NAME,
  CITY,
  STATE,
  COUNTRY,
  LATITUDE,
  LONGITUDE,
  CAPACITY_UNITS,
  CREATED_AT
FROM SUPPLY_CHAIN_DW.RAW.PLANTS;
