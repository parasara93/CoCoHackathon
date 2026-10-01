-- =============================================================================
-- DIM_ROUTE
-- Target: SUPPLY_CHAIN_DW.SILVER.DIM_ROUTE
-- Source: SUPPLY_CHAIN_RAW_DATASET.RAW.ROUTES
-- Grain:  One row per route (ROUTE_ID)
-- Dedup:  N/A — ROUTES is a static reference table
-- Recovered: Exact CTAS from query history (2026-09-29 23:40:44)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_ROUTE AS
SELECT
  ROUTE_ID,
  ORIGIN_TYPE,
  ORIGIN_ID,
  DESTINATION_TYPE,
  DESTINATION_ID,
  DISTANCE_KM,
  EXPECTED_TRANSIT_HOURS,
  ROUTE_RISK_LEVEL,
  CREATED_AT
FROM SUPPLY_CHAIN_RAW_DATASET.RAW.ROUTES;
