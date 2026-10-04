-- =============================================================================
-- V3.7.0 — Add Days of Demand Coverage columns to MART_INVENTORY_RISK
-- =============================================================================
-- Change:       Add 3 columns for demand-based inventory coverage metric
-- Affected:     SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
-- New columns:
--   ORDER_DEMAND_QTY_90D         NUMBER(18,4) — total ordered qty in trailing 90 days
--   AVG_DAILY_ORDER_DEMAND_90D   NUMBER(18,4) — ORDER_DEMAND_QTY_90D / 90
--   DAYS_OF_DEMAND_COVERAGE_90D  NUMBER(18,4) — AVAILABLE_QTY / AVG_DAILY_ORDER_DEMAND_90D
-- Business definition:
--   Days of Demand Coverage (90D) = estimated number of days current available
--   inventory can cover based on average ordered demand over the trailing 90 days.
--   This is a demand-based proxy, NOT physical consumption-based Days of Inventory.
--   NULL coverage = no observed order demand in the 90-day window.
-- Source: SILVER.FACT_ORDER_LINE (ORDER_DATE_KEY, PLANT_ID, PART_ID, ORDERED_QTY)
--   Cancelled lines (LINE_STATUS = 'CANCELLED') are excluded.
--   90-day window: trailing 90 calendar days from MAX(ORDER_DATE_KEY).
-- Preconditions:
--   - MART_INVENTORY_RISK exists (V3.4.0)
--   - SILVER.FACT_ORDER_LINE populated
-- DDL:          ALTER TABLE ADD COLUMN
-- Post-change:  Run gold/populate_mart_inventory_risk.sql (updated), then
--               validations/gold/mart_inventory_risk_checks.sql
-- Rollback:     ALTER TABLE SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK DROP COLUMN
--               ORDER_DEMAND_QTY_90D, AVG_DAILY_ORDER_DEMAND_90D, DAYS_OF_DEMAND_COVERAGE_90D;
-- =============================================================================

ALTER TABLE SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK ADD COLUMN IF NOT EXISTS
    ORDER_DEMAND_QTY_90D         NUMBER(18,4);

ALTER TABLE SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK ADD COLUMN IF NOT EXISTS
    AVG_DAILY_ORDER_DEMAND_90D   NUMBER(18,4);

ALTER TABLE SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK ADD COLUMN IF NOT EXISTS
    DAYS_OF_DEMAND_COVERAGE_90D  NUMBER(18,4);
