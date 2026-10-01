-- =============================================================================
-- DIM_PART
-- Target: SUPPLY_CHAIN_DW.SILVER.DIM_PART
-- Source: SUPPLY_CHAIN_RAW_DATASET.RAW.PARTS
-- Grain:  One row per part (PART_ID)
-- Dedup:  N/A — PARTS is a static reference table
-- Recovered: Exact CTAS from query history (2026-09-29 23:39:23)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_PART AS
SELECT
  PART_ID,
  PART_NAME,
  PART_CATEGORY,
  UNIT_OF_MEASURE,
  STANDARD_COST,
  CRITICALITY,
  CREATED_AT
FROM SUPPLY_CHAIN_RAW_DATASET.RAW.PARTS;
