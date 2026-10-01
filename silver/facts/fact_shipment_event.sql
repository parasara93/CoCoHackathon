-- =============================================================================
-- FACT_SHIPMENT_EVENT
-- Target: SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT
-- Source: SUPPLY_CHAIN_RAW_DATASET.RAW.SHIPMENT_EVENTS
-- Grain:  One row per event (SHIPMENT_EVENT_ID)
-- Dedup:  N/A — preserves genuine event history
-- Derived: EVENT_DATE_KEY = EVENT_TIMESTAMP::DATE
-- Recovered: Exact CTAS from query history (2026-09-29 23:47:22)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT AS
SELECT
  SHIPMENT_EVENT_ID,
  SHIPMENT_ID,
  EVENT_TIMESTAMP,
  EVENT_TIMESTAMP::DATE                  AS EVENT_DATE_KEY,
  EVENT_TYPE,
  LOCATION_LATITUDE,
  LOCATION_LONGITUDE,
  EVENT_DESCRIPTION
FROM SUPPLY_CHAIN_RAW_DATASET.RAW.SHIPMENT_EVENTS;
