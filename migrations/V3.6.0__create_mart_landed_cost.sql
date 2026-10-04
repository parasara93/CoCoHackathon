-- =============================================================================
-- V3.6.0 — Create MART_LANDED_COST
-- =============================================================================
-- Change:       Add estimated landed-cost mart (new table)
-- Affected:     SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST
-- Grain:        One row per SUPPLIER_ID + PART_ID (preferred-supplier attribution)
-- Design:       Quantity-allocated freight from Silver shipment lines + preferred
--               supplier unit cost from BRIDGE_SUPPLIER_PART.
--               Parts without a preferred supplier are excluded.
--               This is an ESTIMATED metric, not accounting-grade landed cost.
-- Preconditions:
--   - SUPPLY_CHAIN_DW.GOLD schema exists (V3.0.0)
--   - SILVER.FACT_SHIPMENT, SILVER.FACT_SHIPMENT_LINE, SILVER.BRIDGE_SUPPLIER_PART exist
-- DDL:          CREATE TABLE IF NOT EXISTS
-- Post-change:  Run gold/populate_mart_landed_cost.sql, then
--               validations/gold/mart_landed_cost_checks.sql
-- Rollback:     DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST;
-- =============================================================================

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST (

    -- Grain / Primary Key
    SUPPLIER_ID                             VARCHAR     NOT NULL,
    PART_ID                                 VARCHAR     NOT NULL,

    -- Metadata
    ANALYSIS_DATE                           DATE        NOT NULL,

    -- Volume metrics
    SHIPMENT_LINE_COUNT                     NUMBER(9,0) NOT NULL,
    SHIPMENT_COUNT                          NUMBER(9,0) NOT NULL,
    TOTAL_SHIPPED_QTY                       NUMBER(18,4) NOT NULL,

    -- Cost components
    SUPPLIER_UNIT_COST                      NUMBER(18,4) NOT NULL,
    TOTAL_ALLOCATED_FREIGHT                 NUMBER(18,4) NOT NULL,
    ALLOCATED_FREIGHT_PER_UNIT              NUMBER(18,4) NOT NULL,

    -- Governed metric
    ESTIMATED_LANDED_UNIT_COST_QTY_ALLOC    NUMBER(18,4) NOT NULL,

    -- Variability
    MIN_LANDED_UNIT_COST                    NUMBER(18,4) NOT NULL,
    MAX_LANDED_UNIT_COST                    NUMBER(18,4) NOT NULL

);
