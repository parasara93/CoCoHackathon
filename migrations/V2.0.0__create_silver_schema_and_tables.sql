-- =============================================================================
-- V2.0.0 — Create Silver Schema and Table Definitions
-- =============================================================================
--
-- Purpose:
--   Creates the SILVER schema and all 15 Silver table structures (empty).
--   Table definitions are derived from the approved Silver transformation
--   SQL in silver/*.sql, with column types validated against actual
--   Snowflake expression return types and RAW column types.
--
-- Objects created:
--   Schema: SUPPLY_CHAIN_DW.SILVER
--   Tables: 15 (7 dimensions, 7 facts, 1 bridge)
--
-- Preconditions:
--   SUPPLY_CHAIN_DW database must exist.
--   SUPPLY_CHAIN_DW.RAW schema and tables must exist (V1.0.0).
--
-- Notes:
--   Tables are created empty. Historical baseline population is performed
--   separately via silver/baseline/ scripts (DML, not migration DDL).
--
-- Rollback:
--   DROP SCHEMA IF EXISTS SUPPLY_CHAIN_DW.SILVER CASCADE;
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_DW.SILVER;

-- ═══════════════════════════════════════════════════════════════════════════════
-- Dimensions
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_DATE (
    DATE_KEY              DATE,
    YEAR                  NUMBER(4,0),
    QUARTER               NUMBER(2,0),
    MONTH                 NUMBER(2,0),
    MONTH_NAME            VARCHAR,
    WEEK_OF_YEAR          NUMBER(2,0),
    DAY_OF_WEEK           NUMBER(2,0),
    DAY_NAME              VARCHAR,
    DAY_OF_MONTH          NUMBER(2,0),
    DAY_OF_YEAR           NUMBER(4,0),
    IS_WEEKEND            BOOLEAN,
    YEAR_QUARTER          VARCHAR,
    YEAR_MONTH            VARCHAR
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_CUSTOMER (
    CUSTOMER_ID           VARCHAR,
    CUSTOMER_NAME         VARCHAR,
    CUSTOMER_SEGMENT      VARCHAR,
    CITY                  VARCHAR,
    STATE                 VARCHAR,
    COUNTRY               VARCHAR,
    LATITUDE              NUMBER(12,6),
    LONGITUDE             NUMBER(12,6),
    CREATED_AT            TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_PLANT (
    PLANT_ID              VARCHAR,
    PLANT_NAME            VARCHAR,
    CITY                  VARCHAR,
    STATE                 VARCHAR,
    COUNTRY               VARCHAR,
    LATITUDE              NUMBER(12,6),
    LONGITUDE             NUMBER(12,6),
    CAPACITY_UNITS        NUMBER(18,4),
    CREATED_AT            TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_PART (
    PART_ID               VARCHAR,
    PART_NAME             VARCHAR,
    PART_CATEGORY         VARCHAR,
    UNIT_OF_MEASURE       VARCHAR,
    STANDARD_COST         NUMBER(18,4),
    CRITICALITY           VARCHAR,
    CREATED_AT            TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_SUPPLIER (
    SUPPLIER_ID           VARCHAR,
    SUPPLIER_NAME         VARCHAR,
    CITY                  VARCHAR,
    STATE                 VARCHAR,
    COUNTRY               VARCHAR,
    SUPPLIER_TIER         VARCHAR,
    SUPPLIER_STATUS       VARCHAR,
    CREATED_AT            TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_CARRIER (
    CARRIER_ID            VARCHAR,
    CARRIER_NAME          VARCHAR,
    CARRIER_TYPE          VARCHAR,
    SERVICE_LEVEL         VARCHAR,
    BASE_COST_PER_KM      NUMBER(18,4),
    ACTIVE_FLAG           BOOLEAN,
    CREATED_AT            TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.DIM_ROUTE (
    ROUTE_ID              VARCHAR,
    ORIGIN_TYPE           VARCHAR,
    ORIGIN_ID             VARCHAR,
    DESTINATION_TYPE      VARCHAR,
    DESTINATION_ID        VARCHAR,
    DISTANCE_KM           NUMBER(18,4),
    EXPECTED_TRANSIT_HOURS NUMBER(18,4),
    ROUTE_RISK_LEVEL      VARCHAR,
    CREATED_AT            TIMESTAMP_NTZ
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Facts
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_ORDER_LINE (
    ORDER_LINE_ID              VARCHAR,
    ORDER_ID                   VARCHAR,
    CUSTOMER_ID                VARCHAR,
    PLANT_ID                   VARCHAR,
    PART_ID                    VARCHAR,
    ORDER_DATE_KEY             DATE,
    REQUESTED_DELIVERY_DATE_KEY DATE,
    ORDER_STATUS               VARCHAR,
    LINE_STATUS                VARCHAR,
    ORDERED_QTY                NUMBER(18,4),
    UNIT_PRICE                 NUMBER(18,4),
    LINE_AMOUNT                NUMBER(18,4),
    ORDER_TOTAL                NUMBER(18,4),
    LINE_CREATED_AT            TIMESTAMP_NTZ,
    LINE_UPDATED_AT            TIMESTAMP_NTZ,
    ORDER_UPDATED_AT           TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT (
    SHIPMENT_ID                VARCHAR,
    SHIPMENT_TYPE              VARCHAR,
    CARRIER_ID                 VARCHAR,
    ROUTE_ID                   VARCHAR,
    SHIPMENT_STATUS            VARCHAR,
    PLANNED_DEPARTURE_AT       TIMESTAMP_NTZ,
    ACTUAL_DEPARTURE_AT        TIMESTAMP_NTZ,
    PLANNED_DELIVERY_AT        TIMESTAMP_NTZ,
    ACTUAL_DELIVERY_AT         TIMESTAMP_NTZ,
    DEPARTURE_DATE_KEY         DATE,
    DELIVERY_DATE_KEY          DATE,
    SHIPPING_COST              NUMBER(18,4),
    ACTUAL_TRANSIT_HOURS       NUMBER(9,0),
    PLANNED_TRANSIT_HOURS      NUMBER(9,0),
    IS_ON_TIME                 BOOLEAN,
    LAST_UPDATED_AT            TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_LINE (
    SHIPMENT_LINE_ID           VARCHAR,
    SHIPMENT_ID                VARCHAR,
    ORDER_LINE_ID              VARCHAR,
    PART_ID                    VARCHAR,
    SHIPPED_QTY                NUMBER(18,4),
    CREATED_AT                 TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_SHIPMENT_EVENT (
    SHIPMENT_EVENT_ID          VARCHAR,
    SHIPMENT_ID                VARCHAR,
    EVENT_TIMESTAMP            TIMESTAMP_NTZ,
    EVENT_DATE_KEY             DATE,
    EVENT_TYPE                 VARCHAR,
    LOCATION_LATITUDE          NUMBER(12,6),
    LOCATION_LONGITUDE         NUMBER(12,6),
    EVENT_DESCRIPTION          VARCHAR
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_INVENTORY_SNAPSHOT (
    PLANT_ID                   VARCHAR,
    PART_ID                    VARCHAR,
    ON_HAND_QTY                NUMBER(18,4),
    RESERVED_QTY               NUMBER(18,4),
    AVAILABLE_QTY              NUMBER(18,4),
    SAFETY_STOCK               NUMBER(18,4),
    REORDER_POINT              NUMBER(18,4),
    INVENTORY_STATUS           VARCHAR,
    NEEDS_REORDER              BOOLEAN,
    BELOW_SAFETY_STOCK         BOOLEAN,
    LAST_UPDATED_AT            TIMESTAMP_NTZ,
    SNAPSHOT_DATE_KEY          DATE
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_SUPPLIER_PERFORMANCE (
    SUPPLIER_PERFORMANCE_ID    VARCHAR,
    SUPPLIER_ID                VARCHAR,
    MEASUREMENT_DATE_KEY       DATE,
    AVG_LEAD_TIME_DAYS         NUMBER(18,4),
    ON_TIME_DELIVERY_PCT       NUMBER(18,4),
    QUALITY_SCORE              NUMBER(18,4),
    FILL_RATE_PCT              NUMBER(18,4),
    RISK_SCORE                 NUMBER(18,4),
    LAST_UPDATED_AT            TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.FACT_VEHICLE_TELEMETRY (
    TELEMETRY_ID               VARCHAR,
    VEHICLE_ID                 VARCHAR,
    SHIPMENT_ID                VARCHAR,
    EVENT_TIMESTAMP            TIMESTAMP_NTZ,
    EVENT_DATE_KEY             DATE,
    LATITUDE                   NUMBER(12,6),
    LONGITUDE                  NUMBER(12,6),
    SPEED_KMPH                 NUMBER(18,4),
    VEHICLE_STATUS             VARCHAR,
    DISTANCE_TRAVELLED_KM      NUMBER(18,4)
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Bridge
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE SUPPLY_CHAIN_DW.SILVER.BRIDGE_SUPPLIER_PART (
    SUPPLIER_ID                VARCHAR,
    PART_ID                    VARCHAR,
    SUPPLIER_UNIT_COST         NUMBER(18,4),
    BASE_LEAD_TIME_DAYS        NUMBER(18,4),
    MINIMUM_ORDER_QTY          NUMBER(18,4),
    PREFERRED_SUPPLIER_FLAG    BOOLEAN,
    ACTIVE_FLAG                BOOLEAN,
    LAST_UPDATED_AT            TIMESTAMP_NTZ
);
