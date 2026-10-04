-- =============================================================================
-- V3.4.0 -- Create MART_ORDER_FULFILLMENT (structure only)
-- =============================================================================
--
-- ## Change purpose
-- Fourth Gold analytical mart: order-level fulfillment performance.
-- DDL-only; population handled by gold/populate_mart_order_fulfillment.sql.
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT
--
-- ## Grain
-- One row per ORDER_ID
--
-- ## Design reference
-- Reuses archived V2.5.0 design (37 columns). Two-branch architecture:
-- Branch 1 (line fulfillment + lateness → ORDER_ID) and
-- Branch 2 (shipment metrics → ORDER_ID).
--
-- ## Preconditions
-- V3.0.0 (GOLD schema) must be applied.
-- Silver tables must exist in SUPPLY_CHAIN_DW.SILVER.
--
-- ## DDL

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT (
    -- 1. Identity (2)
    ORDER_ID                    VARCHAR         NOT NULL,
    ANALYSIS_AS_OF_DATE         DATE            NOT NULL,

    -- 2. Order attributes (7)
    CUSTOMER_ID                 VARCHAR,
    CUSTOMER_NAME               VARCHAR,
    CUSTOMER_SEGMENT            VARCHAR,
    PLANT_ID                    VARCHAR,
    PLANT_NAME                  VARCHAR,
    ORDER_DATE                  DATE,
    REQUESTED_DELIVERY_DATE     DATE,

    -- 3. Fulfillment classification (1)
    FULFILLMENT_STATE           VARCHAR         NOT NULL,

    -- 4. Quantity metrics (10)
    TOTAL_ORDER_LINE_COUNT      NUMBER(9,0)     NOT NULL,
    CANCELLED_LINE_COUNT        NUMBER(9,0)     NOT NULL,
    ACTIVE_LINE_COUNT           NUMBER(9,0)     NOT NULL,
    ORDERED_QTY                 NUMBER(18,4)    NOT NULL,
    ACTIVE_ORDERED_QTY          NUMBER(18,4)    NOT NULL,
    RAW_SHIPPED_QTY             NUMBER(18,4)    NOT NULL,
    EFFECTIVE_SHIPPED_QTY       NUMBER(18,4)    NOT NULL,
    OUTSTANDING_QTY             NUMBER(18,4)    NOT NULL,
    OVER_SHIPPED_QTY            NUMBER(18,4)    NOT NULL,
    FULFILLMENT_PCT             NUMBER(18,2),

    -- 5. Value metrics (3)
    ORDER_VALUE                 NUMBER(18,4)    NOT NULL,
    ACTIVE_ORDER_VALUE          NUMBER(18,4)    NOT NULL,
    OUTSTANDING_VALUE           NUMBER(18,4)    NOT NULL,

    -- 6. Shipment metrics (2)
    SHIPMENT_COUNT              NUMBER(9,0)     NOT NULL,
    LATE_SHIPMENT_COUNT         NUMBER(9,0)     NOT NULL,

    -- 7. Delay metrics (3)
    CURRENT_DELAY_DAYS          NUMBER(9,0),
    MAX_DELIVERED_DELAY_DAYS    NUMBER(9,0),
    LAST_ACTUAL_DELIVERY_DATE   DATE,

    -- 8. Explainability flags (9)
    IS_FULFILLED                BOOLEAN         NOT NULL,
    IS_PARTIALLY_FULFILLED      BOOLEAN         NOT NULL,
    IS_UNFULFILLED              BOOLEAN         NOT NULL,
    IS_CANCELLED                BOOLEAN         NOT NULL,
    IS_CURRENT_LATE             BOOLEAN         NOT NULL,
    IS_DELIVERED_LATE           BOOLEAN         NOT NULL,
    IS_LATE                     BOOLEAN         NOT NULL,
    HAS_DELAYED_SHIPMENT        BOOLEAN         NOT NULL,
    HAS_OVER_SHIPMENT           BOOLEAN         NOT NULL
);

-- ## Post-change validation
-- Table should exist with 37 columns and 0 rows.

-- ## Rollback / manual recovery
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT;
