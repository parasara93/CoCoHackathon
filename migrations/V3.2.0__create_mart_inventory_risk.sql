-- =============================================================================
-- V3.2.0 -- Create MART_INVENTORY_RISK (structure only)
-- =============================================================================
--
-- ## Change purpose
-- Second Gold analytical mart: plant+part inventory position risk and demand
-- exposure. DDL-only; population handled by gold/populate_mart_inventory_risk.sql.
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
--
-- ## Grain
-- One row per PLANT_ID + PART_ID
--
-- ## Design reference
-- Reuses archived V2.7.0 design (24 columns). Two pre-aggregation branches
-- (supplier count, demand exposure) plus dimension enrichment on an
-- FACT_INVENTORY_SNAPSHOT base.
--
-- ## Preconditions
-- V3.0.0 (GOLD schema) must be applied.
-- Silver tables must exist in SUPPLY_CHAIN_DW.SILVER.
--
-- ## DDL

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK (
    -- 1. Identity / Context (3)
    PLANT_ID                    VARCHAR         NOT NULL,
    PART_ID                     VARCHAR         NOT NULL,
    ANALYSIS_AS_OF_DATE         DATE            NOT NULL,

    -- 2. Plant Attributes (1)
    PLANT_NAME                  VARCHAR,

    -- 3. Part Attributes (3)
    PART_NAME                   VARCHAR,
    PART_CATEGORY               VARCHAR,
    CRITICALITY                 VARCHAR,

    -- 4. Inventory Facts (6)
    ON_HAND_QTY                 NUMBER(18,4)    NOT NULL,
    RESERVED_QTY                NUMBER(18,4)    NOT NULL,
    AVAILABLE_QTY               NUMBER(18,4)    NOT NULL,
    SAFETY_STOCK                NUMBER(18,4)    NOT NULL,
    REORDER_POINT               NUMBER(18,4)    NOT NULL,
    INVENTORY_STATUS            VARCHAR         NOT NULL,
    SNAPSHOT_DATE_KEY           DATE,

    -- 5. Risk Derivations (5)
    BELOW_SAFETY_STOCK_QTY      NUMBER(18,4)    NOT NULL,
    SHORTAGE_QTY                NUMBER(18,4)    NOT NULL,
    NEEDS_REORDER               BOOLEAN         NOT NULL,
    BELOW_SAFETY_STOCK          BOOLEAN         NOT NULL,
    IS_OUT_OF_STOCK             BOOLEAN         NOT NULL,

    -- 6. Supplier Context (1)
    ACTIVE_SUPPLIER_COUNT       NUMBER(9,0)     NOT NULL,

    -- 7. Demand Exposure (5)
    ACTIVE_ORDER_COUNT          NUMBER(9,0)     NOT NULL,
    ACTIVE_ORDERED_QTY          NUMBER(18,4)    NOT NULL,
    OUTSTANDING_ORDER_QTY       NUMBER(18,4)    NOT NULL,
    OUTSTANDING_ORDER_VALUE     NUMBER(18,4)    NOT NULL
);

-- ## Post-change validation
-- Table should exist with 24 columns and 0 rows.

-- ## Rollback / manual recovery
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK;
