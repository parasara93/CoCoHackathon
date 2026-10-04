-- =============================================================================
-- V1.0.0 — Create RAW Schema and 15 Operational RAW Tables
-- =============================================================================
--
-- Purpose:
--   Creates the RAW landing schema and all 15 operational tables for
--   historical batch loading and future CDC ingestion. Table structures
--   are derived from generator/synth_generator.py TABLE_SCHEMAS.
--
-- Objects created:
--   Schema: SUPPLY_CHAIN_DW.RAW
--   Tables: 15 (see below)
--
-- Preconditions:
--   SUPPLY_CHAIN_DW database must exist (bootstrap prerequisite).
--
-- RAW design rules:
--   - Append-only: no PK/UNIQUE constraints, no deduplication at RAW.
--   - Every table includes generator CDC metadata (_INGEST_OPERATION,
--     _INGEST_BATCH_TS) and Snowflake load metadata (LOAD_BATCH_ID,
--     SOURCE_FILE_NAME, SOURCE_BATCH_TYPE, SOURCE_BATCH_TS, LOADED_AT).
--   - Business column values are never modified at RAW.
--
-- Rollback:
--   DROP SCHEMA IF EXISTS SUPPLY_CHAIN_DW.RAW CASCADE;
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_DW.RAW;

-- ═══════════════════════════════════════════════════════════════════════════════
-- ERP Domain
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE SUPPLY_CHAIN_DW.RAW.CUSTOMERS (
    CUSTOMER_ID             VARCHAR,
    CUSTOMER_NAME           VARCHAR,
    CUSTOMER_SEGMENT        VARCHAR,
    CITY                    VARCHAR,
    STATE                   VARCHAR,
    COUNTRY                 VARCHAR,
    LATITUDE                NUMBER(12,6),
    LONGITUDE               NUMBER(12,6),
    CREATED_AT              TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.PLANTS (
    PLANT_ID                VARCHAR,
    PLANT_NAME              VARCHAR,
    CITY                    VARCHAR,
    STATE                   VARCHAR,
    COUNTRY                 VARCHAR,
    LATITUDE                NUMBER(12,6),
    LONGITUDE               NUMBER(12,6),
    CAPACITY_UNITS          NUMBER(18,4),
    CREATED_AT              TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.ORDERS (
    ORDER_ID                VARCHAR,
    CUSTOMER_ID             VARCHAR,
    PLANT_ID                VARCHAR,
    ORDER_DATE              TIMESTAMP_NTZ,
    REQUESTED_DELIVERY_DATE DATE,
    ORDER_STATUS            VARCHAR,
    ORDER_TOTAL             NUMBER(18,4),
    LAST_UPDATED_AT         TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.ORDER_LINES (
    ORDER_LINE_ID           VARCHAR,
    ORDER_ID                VARCHAR,
    PART_ID                 VARCHAR,
    ORDERED_QTY             NUMBER(18,4),
    UNIT_PRICE              NUMBER(18,4),
    LINE_AMOUNT             NUMBER(18,4),
    LINE_STATUS             VARCHAR,
    CREATED_AT              TIMESTAMP_NTZ,
    LAST_UPDATED_AT         TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.INVENTORY (
    PLANT_ID                VARCHAR,
    PART_ID                 VARCHAR,
    ON_HAND_QTY             NUMBER(18,4),
    RESERVED_QTY            NUMBER(18,4),
    AVAILABLE_QTY           NUMBER(18,4),
    SAFETY_STOCK            NUMBER(18,4),
    REORDER_POINT           NUMBER(18,4),
    INVENTORY_STATUS        VARCHAR,
    LAST_UPDATED_AT         TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Supplier Domain
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE SUPPLY_CHAIN_DW.RAW.SUPPLIERS (
    SUPPLIER_ID             VARCHAR,
    SUPPLIER_NAME           VARCHAR,
    CITY                    VARCHAR,
    STATE                   VARCHAR,
    COUNTRY                 VARCHAR,
    SUPPLIER_TIER           VARCHAR,
    SUPPLIER_STATUS         VARCHAR,
    CREATED_AT              TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.PARTS (
    PART_ID                 VARCHAR,
    PART_NAME               VARCHAR,
    PART_CATEGORY           VARCHAR,
    UNIT_OF_MEASURE         VARCHAR,
    STANDARD_COST           NUMBER(18,4),
    CRITICALITY             VARCHAR,
    CREATED_AT              TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.SUPPLIER_PARTS (
    SUPPLIER_ID             VARCHAR,
    PART_ID                 VARCHAR,
    SUPPLIER_UNIT_COST      NUMBER(18,4),
    BASE_LEAD_TIME_DAYS     NUMBER(18,4),
    MINIMUM_ORDER_QTY       NUMBER(18,4),
    PREFERRED_SUPPLIER_FLAG BOOLEAN,
    ACTIVE_FLAG             BOOLEAN,
    LAST_UPDATED_AT         TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.SUPPLIER_PERFORMANCE (
    SUPPLIER_PERFORMANCE_ID VARCHAR,
    SUPPLIER_ID             VARCHAR,
    MEASUREMENT_DATE        DATE,
    AVG_LEAD_TIME_DAYS      NUMBER(18,4),
    ON_TIME_DELIVERY_PCT    NUMBER(18,4),
    QUALITY_SCORE           NUMBER(18,4),
    FILL_RATE_PCT           NUMBER(18,4),
    RISK_SCORE              NUMBER(18,4),
    LAST_UPDATED_AT         TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Logistics Domain
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE SUPPLY_CHAIN_DW.RAW.CARRIERS (
    CARRIER_ID              VARCHAR,
    CARRIER_NAME            VARCHAR,
    CARRIER_TYPE            VARCHAR,
    SERVICE_LEVEL           VARCHAR,
    BASE_COST_PER_KM        NUMBER(18,4),
    ACTIVE_FLAG             BOOLEAN,
    CREATED_AT              TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.ROUTES (
    ROUTE_ID                VARCHAR,
    ORIGIN_TYPE             VARCHAR,
    ORIGIN_ID               VARCHAR,
    DESTINATION_TYPE        VARCHAR,
    DESTINATION_ID          VARCHAR,
    DISTANCE_KM             NUMBER(18,4),
    EXPECTED_TRANSIT_HOURS  NUMBER(18,4),
    ROUTE_RISK_LEVEL        VARCHAR,
    CREATED_AT              TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.SHIPMENTS (
    SHIPMENT_ID             VARCHAR,
    SHIPMENT_TYPE           VARCHAR,
    CARRIER_ID              VARCHAR,
    ROUTE_ID                VARCHAR,
    SHIPMENT_STATUS         VARCHAR,
    PLANNED_DEPARTURE_AT    TIMESTAMP_NTZ,
    ACTUAL_DEPARTURE_AT     TIMESTAMP_NTZ,
    PLANNED_DELIVERY_AT     TIMESTAMP_NTZ,
    ACTUAL_DELIVERY_AT      TIMESTAMP_NTZ,
    SHIPPING_COST           NUMBER(18,4),
    LAST_UPDATED_AT         TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.SHIPMENT_LINES (
    SHIPMENT_LINE_ID        VARCHAR,
    SHIPMENT_ID             VARCHAR,
    ORDER_LINE_ID           VARCHAR,
    PART_ID                 VARCHAR,
    SHIPPED_QTY             NUMBER(18,4),
    CREATED_AT              TIMESTAMP_NTZ,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

CREATE TABLE SUPPLY_CHAIN_DW.RAW.SHIPMENT_EVENTS (
    SHIPMENT_EVENT_ID       VARCHAR,
    SHIPMENT_ID             VARCHAR,
    EVENT_TIMESTAMP         TIMESTAMP_NTZ,
    EVENT_TYPE              VARCHAR,
    LOCATION_LATITUDE       NUMBER(12,6),
    LOCATION_LONGITUDE      NUMBER(12,6),
    EVENT_DESCRIPTION       VARCHAR,
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- IoT Domain
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE SUPPLY_CHAIN_DW.RAW.VEHICLE_TELEMETRY (
    TELEMETRY_ID            VARCHAR,
    VEHICLE_ID              VARCHAR,
    SHIPMENT_ID             VARCHAR,
    EVENT_TIMESTAMP         TIMESTAMP_NTZ,
    LATITUDE                NUMBER(12,6),
    LONGITUDE               NUMBER(12,6),
    SPEED_KMPH              NUMBER(18,4),
    VEHICLE_STATUS          VARCHAR,
    DISTANCE_TRAVELLED_KM   NUMBER(18,4),
    _INGEST_OPERATION       VARCHAR(10),
    _INGEST_BATCH_TS        TIMESTAMP_NTZ,
    LOAD_BATCH_ID           VARCHAR(30),
    SOURCE_FILE_NAME        VARCHAR(500),
    SOURCE_BATCH_TYPE       VARCHAR(20),
    SOURCE_BATCH_TS         TIMESTAMP_NTZ,
    LOADED_AT               TIMESTAMP_NTZ
);
