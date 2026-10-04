-- =============================================================================
-- V3.3.0 -- Create MART_LOGISTICS_PERFORMANCE (structure only)
-- =============================================================================
--
-- ## Change purpose
-- Third Gold analytical mart: shipment-level logistics performance and
-- disruption metrics. DDL-only; population handled by
-- gold/populate_mart_logistics_performance.sql.
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
--
-- ## Grain
-- One row per SHIPMENT_ID
--
-- ## Design reference
-- Reuses archived V2.6.0 design (29 columns). Two pre-aggregation branches
-- (event counts, order impact) plus dimension enrichment on a FACT_SHIPMENT
-- base.
--
-- ## Preconditions
-- V3.0.0 (GOLD schema) must be applied.
-- Silver tables must exist in SUPPLY_CHAIN_DW.SILVER.
--
-- ## DDL

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE (
    -- 1. Identity (2)
    SHIPMENT_ID                 VARCHAR         NOT NULL,
    ANALYSIS_AS_OF_DATE         DATE            NOT NULL,

    -- 2. Shipment attributes (4)
    SHIPMENT_TYPE               VARCHAR,
    SHIPMENT_STATUS             VARCHAR,
    CARRIER_ID                  VARCHAR,
    ROUTE_ID                    VARCHAR,

    -- 3. Carrier attributes (3)
    CARRIER_NAME                VARCHAR,
    CARRIER_TYPE                VARCHAR,
    SERVICE_LEVEL               VARCHAR,

    -- 4. Route attributes (6)
    ORIGIN_TYPE                 VARCHAR,
    ORIGIN_ID                   VARCHAR,
    DESTINATION_TYPE            VARCHAR,
    DESTINATION_ID              VARCHAR,
    DISTANCE_KM                 NUMBER(18,4),
    ROUTE_RISK_LEVEL            VARCHAR,

    -- 5. Timing (4)
    PLANNED_DEPARTURE_AT        TIMESTAMP_NTZ,
    ACTUAL_DEPARTURE_AT         TIMESTAMP_NTZ,
    PLANNED_DELIVERY_AT         TIMESTAMP_NTZ,
    ACTUAL_DELIVERY_AT          TIMESTAMP_NTZ,

    -- 6. Cost (1)
    SHIPPING_COST               NUMBER(18,4),

    -- 7. Performance metrics (5)
    IS_ON_TIME                  BOOLEAN,
    PLANNED_TRANSIT_HOURS       NUMBER(9,0),
    ACTUAL_TRANSIT_HOURS        NUMBER(9,0),
    TRANSIT_VARIANCE_HOURS      NUMBER(9,0),
    DEPARTURE_DELAY_HOURS       NUMBER(9,0),
    DELIVERY_DELAY_HOURS        NUMBER(9,0),

    -- 8. Disruption events (2)
    ROUTE_DEVIATION_EVENT_COUNT NUMBER(9,0)     NOT NULL,
    DELAY_REPORTED_EVENT_COUNT  NUMBER(9,0)     NOT NULL,

    -- 9. Order impact (1)
    DISTINCT_ORDER_COUNT        NUMBER(9,0)     NOT NULL
);

-- ## Post-change validation
-- Table should exist with 29 columns and 0 rows.

-- ## Rollback / manual recovery
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE;
