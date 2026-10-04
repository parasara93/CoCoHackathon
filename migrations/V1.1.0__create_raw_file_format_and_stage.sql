-- =============================================================================
-- V1.1.0 — Create CSV File Format and External Stage
-- =============================================================================
--
-- Purpose:
--   Creates the CSV file format and S3 external stage required for loading
--   historical and incremental data into the RAW tables.
--
-- Objects created:
--   File format: SUPPLY_CHAIN_DW.RAW.CSV_FORMAT
--   Stage:       SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE
--
-- Preconditions:
--   - SUPPLY_CHAIN_DW.RAW schema must exist (V1.0.0).
--   - SUPPLY_CHAIN_S3_INTEGRATION must exist (environment bootstrap).
--
-- Post-change validation:
--   SHOW FILE FORMATS IN SCHEMA SUPPLY_CHAIN_DW.RAW;
--   SHOW STAGES IN SCHEMA SUPPLY_CHAIN_DW.RAW;
--   LIST @SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE;
--
-- Rollback:
--   DROP STAGE IF EXISTS SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE;
--   DROP FILE FORMAT IF EXISTS SUPPLY_CHAIN_DW.RAW.CSV_FORMAT;
-- =============================================================================

CREATE FILE FORMAT SUPPLY_CHAIN_DW.RAW.CSV_FORMAT
  TYPE = 'CSV'
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  SKIP_HEADER = 1
  NULL_IF = ('', 'NULL', 'null')
  EMPTY_FIELD_AS_NULL = TRUE
  TRIM_SPACE = TRUE;

CREATE STAGE SUPPLY_CHAIN_DW.RAW.SUPPLY_CHAIN_STAGE
  STORAGE_INTEGRATION = SUPPLY_CHAIN_S3_INTEGRATION
  URL = 's3://snowflake-coco-hackathon/supply-chain-medium/'
  FILE_FORMAT = SUPPLY_CHAIN_DW.RAW.CSV_FORMAT;
