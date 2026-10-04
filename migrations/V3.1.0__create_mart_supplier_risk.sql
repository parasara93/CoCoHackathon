-- =============================================================================
-- V3.1.0 -- Create MART_SUPPLIER_RISK (structure only)
-- =============================================================================
--
-- ## Change purpose
-- First Gold analytical mart: supplier-level risk and exposure summary.
-- DDL-only migration; population is handled by a separate script.
-- Incorporates the V2.4.0 severity additions from day one (50 columns).
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK
--
-- ## Grain
-- One row per SUPPLIER_ID
--
-- ## Design reference
-- Reuses archived V2.3.0 + V2.4.0 design. Five independent pre-aggregation
-- branches joined 1:1 on SUPPLIER_ID. See gold/populate_mart_supplier_risk.sql
-- for the population logic.
--
-- ## Preconditions
-- V3.0.0 (GOLD schema) must be applied.
-- Silver tables must exist in SUPPLY_CHAIN_DW.SILVER.
--
-- ## DDL

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK (
    -- 1. Metadata (1)
    ANALYSIS_AS_OF_DATE             DATE            NOT NULL,

    -- 2. Supplier attributes (4)
    SUPPLIER_ID                     VARCHAR         NOT NULL,
    SUPPLIER_NAME                   VARCHAR         NOT NULL,
    SUPPLIER_TIER                   VARCHAR,
    SUPPLIER_STATUS                 VARCHAR,

    -- 3. Supplier performance trends (15)
    LATEST_ON_TIME_DELIVERY_PCT     NUMBER(18,4),
    EARLIEST_ON_TIME_DELIVERY_PCT   NUMBER(18,4),
    ON_TIME_DELIVERY_PCT_CHANGE     NUMBER(18,4),
    LATEST_QUALITY_SCORE            NUMBER(18,4),
    EARLIEST_QUALITY_SCORE          NUMBER(18,4),
    QUALITY_SCORE_CHANGE            NUMBER(18,4),
    LATEST_AVG_LEAD_TIME_DAYS       NUMBER(18,4),
    EARLIEST_AVG_LEAD_TIME_DAYS     NUMBER(18,4),
    LEAD_TIME_CHANGE_DAYS           NUMBER(18,4),
    LATEST_FILL_RATE_PCT            NUMBER(18,4),
    LATEST_RISK_SCORE               NUMBER(18,4),
    EARLIEST_RISK_SCORE             NUMBER(18,4),
    RISK_SCORE_CHANGE               NUMBER(18,4),
    MEASUREMENT_PERIOD_COUNT        NUMBER(9,0)     NOT NULL,
    LATEST_MEASUREMENT_DATE         DATE,

    -- 4. Dependency exposure (2)
    SUPPLIED_PART_COUNT             NUMBER(9,0)     NOT NULL,
    PREFERRED_PART_COUNT            NUMBER(9,0)     NOT NULL,

    -- 5. Inventory exposure (6)
    EXPOSED_PLANT_COUNT             NUMBER(9,0)     NOT NULL,
    INVENTORY_PART_COUNT            NUMBER(9,0)     NOT NULL,
    EXPOSED_INVENTORY_QTY           NUMBER(18,4)    NOT NULL,
    EXPOSED_INVENTORY_POSITION_COUNT NUMBER(9,0)    NOT NULL,
    LOW_INVENTORY_POSITION_COUNT    NUMBER(9,0)     NOT NULL,
    LOW_INVENTORY_EXPOSURE_PCT      NUMBER(18,2),

    -- 6. Order exposure (9)
    EXPOSED_ORDER_COUNT             NUMBER(9,0)     NOT NULL,
    EXPOSED_ORDER_LINE_COUNT        NUMBER(9,0)     NOT NULL,
    EXPOSED_ORDERED_QTY             NUMBER(18,4)    NOT NULL,
    ACTIVE_EXPOSED_ORDER_VALUE      NUMBER(18,4)    NOT NULL,
    EXPOSED_OUTSTANDING_QTY         NUMBER(18,4)    NOT NULL,
    EXPOSED_OUTSTANDING_VALUE       NUMBER(18,4)    NOT NULL,
    ACTIVE_EXPOSED_OUTSTANDING_VALUE NUMBER(18,4)   NOT NULL,
    OUTSTANDING_EXPOSURE_PCT        NUMBER(18,2),
    EXPOSED_LATE_ORDER_LINE_COUNT   NUMBER(9,0)     NOT NULL,

    -- 7. Shipment exposure (3)
    EXPOSED_SHIPMENT_COUNT          NUMBER(9,0)     NOT NULL,
    LATE_SHIPMENT_COUNT             NUMBER(9,0)     NOT NULL,
    LATE_SHIPMENT_PCT               NUMBER(18,2),

    -- 8. Explainability flags (11)
    HAS_OTD_DETERIORATION                   BOOLEAN NOT NULL,
    HAS_QUALITY_DETERIORATION               BOOLEAN NOT NULL,
    HAS_LEAD_TIME_DETERIORATION             BOOLEAN NOT NULL,
    HAS_RISK_SCORE_INCREASE                 BOOLEAN NOT NULL,
    HAS_SUPPLIER_PERFORMANCE_DETERIORATION  BOOLEAN NOT NULL,
    HAS_LATE_SHIPMENT_EXPOSURE              BOOLEAN NOT NULL,
    HAS_OUTSTANDING_ORDER_EXPOSURE          BOOLEAN NOT NULL,
    HAS_LOW_INVENTORY_EXPOSURE              BOOLEAN NOT NULL,
    HAS_DOWNSTREAM_EXPOSURE                 BOOLEAN NOT NULL,
    IS_SUPPLIER_AT_RISK                     BOOLEAN NOT NULL
);

-- ## Post-change validation
-- Table should exist with 50 columns and 0 rows.
-- SELECT COUNT(*) FROM SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK; -- 0

-- ## Rollback / manual recovery
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK;
