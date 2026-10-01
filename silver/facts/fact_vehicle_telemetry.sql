-- =============================================================================
-- FACT_VEHICLE_TELEMETRY
-- Target: SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY
-- Source: SUPPLY_CHAIN_RAW_DATASET.RAW.VEHICLE_TELEMETRY
-- Grain:  One row per telemetry reading (TELEMETRY_ID)
-- Dedup:  N/A — preserves genuine telemetry history
-- Derived: EVENT_DATE_KEY = EVENT_TIMESTAMP::DATE
-- Recovered: Exact CTAS from query history (2026-09-29 23:50:06)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY AS
SELECT
  TELEMETRY_ID,
  VEHICLE_ID,
  SHIPMENT_ID,
  EVENT_TIMESTAMP,
  EVENT_TIMESTAMP::DATE                  AS EVENT_DATE_KEY,
  LATITUDE,
  LONGITUDE,
  SPEED_KMPH,
  VEHICLE_STATUS,
  DISTANCE_TRAVELLED_KM
FROM SUPPLY_CHAIN_RAW_DATASET.RAW.VEHICLE_TELEMETRY;
