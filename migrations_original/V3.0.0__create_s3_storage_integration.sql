-- =============================================================================
-- V3.0.0 — Create S3 Storage Integration (Bootstrap)
-- =============================================================================
--
-- Purpose:
--   Creates the account-level storage integration for read access to the
--   supply-chain-medium dataset on S3. This is a bootstrap/infrastructure
--   object required before any external stage or data loading can occur.
--
-- Object:
--   SUPPLY_CHAIN_S3_INTEGRATION (account-level storage integration)
--
-- Preconditions:
--   - Brand-new Snowflake account with ACCOUNTADMIN role
--   - AWS IAM role arn:aws:iam::033842784914:role/SnowflakeHackathonRole
--     must exist and be configured with the trust policy using the
--     STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID returned by
--     DESCRIBE INTEGRATION after creation.
--
-- Post-change validation:
--   DESCRIBE INTEGRATION SUPPLY_CHAIN_S3_INTEGRATION;
--   Confirm STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID are present.
--
-- Rollback:
--   DROP STORAGE INTEGRATION IF EXISTS SUPPLY_CHAIN_S3_INTEGRATION;
-- =============================================================================

CREATE STORAGE INTEGRATION SUPPLY_CHAIN_S3_INTEGRATION
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::033842784914:role/SnowflakeHackathonRole'
  STORAGE_ALLOWED_LOCATIONS = ('s3://snowflake-coco-hackathon/supply-chain-medium/');
