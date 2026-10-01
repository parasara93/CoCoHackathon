-- =============================================================================
-- DIM_CUSTOMER
-- Target: SUPPLY_CHAIN_DW.SILVER.DIM_CUSTOMER
-- Source: SUPPLY_CHAIN_RAW_DATASET.RAW.CUSTOMERS
-- Grain:  One row per customer (CUSTOMER_ID)
-- Dedup:  N/A — CUSTOMERS is a static reference table
-- Recovered: Exact CTAS from query history (2026-09-29 23:39:06)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_CUSTOMER AS
SELECT
  CUSTOMER_ID,
  CUSTOMER_NAME,
  CUSTOMER_SEGMENT,
  CITY,
  STATE,
  COUNTRY,
  LATITUDE,
  LONGITUDE,
  CREATED_AT
FROM SUPPLY_CHAIN_RAW_DATASET.RAW.CUSTOMERS;
