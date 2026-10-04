-- =============================================================================
-- DIM_DATE
-- Target: SUPPLY_CHAIN_DW.SILVER.DIM_DATE
-- Source: Generated date spine (2025-01-01 to 2026-12-31)
-- Grain:  One row per calendar date (DATE_KEY)
-- Dedup:  N/A — generated, not sourced from RAW
-- Recovered: Exact CTAS from query history (2026-09-29 23:37:16)
-- =============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_DATE AS
WITH date_spine AS (
  SELECT DATEADD(DAY, SEQ4(), '2025-01-01'::DATE) AS DATE_KEY
  FROM TABLE(GENERATOR(ROWCOUNT => 731))  -- 2 years
)
SELECT
  DATE_KEY,
  YEAR(DATE_KEY)                          AS YEAR,
  QUARTER(DATE_KEY)                       AS QUARTER,
  MONTH(DATE_KEY)                         AS MONTH,
  MONTHNAME(DATE_KEY)                     AS MONTH_NAME,
  WEEKOFYEAR(DATE_KEY)                    AS WEEK_OF_YEAR,
  DAYOFWEEK(DATE_KEY)                     AS DAY_OF_WEEK,
  DAYNAME(DATE_KEY)                       AS DAY_NAME,
  DAY(DATE_KEY)                           AS DAY_OF_MONTH,
  DAYOFYEAR(DATE_KEY)                     AS DAY_OF_YEAR,
  CASE WHEN DAYOFWEEK(DATE_KEY) IN (0,6) THEN TRUE ELSE FALSE END AS IS_WEEKEND,
  TO_CHAR(DATE_KEY, 'YYYY-Q')            AS YEAR_QUARTER,
  TO_CHAR(DATE_KEY, 'YYYY-MM')           AS YEAR_MONTH
FROM date_spine
WHERE DATE_KEY <= '2026-12-31';
