-- =============================================================================
-- V3.5.0 -- Create MART_CUSTOMER_IMPACT (structure only)
-- =============================================================================
--
-- ## Change purpose
-- Fifth and final Gold analytical mart: customer-level supply-chain impact
-- summary. DDL-only; population handled by
-- gold/populate_mart_customer_impact.sql.
--
-- ## Affected object(s)
-- SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT
--
-- ## Grain
-- One row per CUSTOMER_ID
--
-- ## Design reference
-- Reuses archived V2.1.0 design (34 columns). Two branches:
-- Branch A (order/fulfillment → customer) and Branch B (shipment stats).
--
-- ## Preconditions
-- V3.0.0 (GOLD schema) must be applied.
-- Silver tables must exist in SUPPLY_CHAIN_DW.SILVER.
--
-- ## DDL

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT (
    -- 1. Metadata (1)
    ANALYSIS_AS_OF_DATE         DATE            NOT NULL,

    -- 2. Customer attributes (3)
    CUSTOMER_ID                 VARCHAR         NOT NULL,
    CUSTOMER_NAME               VARCHAR         NOT NULL,
    CUSTOMER_SEGMENT            VARCHAR,

    -- 3. Order counts (9)
    TOTAL_ORDER_COUNT           NUMBER(9,0)     NOT NULL,
    OPEN_ORDER_COUNT            NUMBER(9,0)     NOT NULL,
    FULFILLED_ORDER_COUNT       NUMBER(9,0)     NOT NULL,
    PARTIALLY_FULFILLED_ORDER_COUNT NUMBER(9,0) NOT NULL,
    UNFULFILLED_ORDER_COUNT     NUMBER(9,0)     NOT NULL,
    CANCELLED_ORDER_COUNT       NUMBER(9,0)     NOT NULL,
    CURRENT_LATE_ORDER_COUNT    NUMBER(9,0)     NOT NULL,
    DELIVERED_LATE_ORDER_COUNT  NUMBER(9,0)     NOT NULL,
    TOTAL_LATE_ORDER_COUNT      NUMBER(9,0)     NOT NULL,

    -- 4. Quantity metrics (4)
    ACTIVE_ORDERED_QTY          NUMBER(18,4)    NOT NULL,
    ACTIVE_SHIPPED_QTY          NUMBER(18,4)    NOT NULL,
    OUTSTANDING_QTY             NUMBER(18,4)    NOT NULL,
    FULFILLMENT_PCT             NUMBER(18,2),

    -- 5. Value metrics (4)
    ACTIVE_ORDER_VALUE          NUMBER(18,4)    NOT NULL,
    OUTSTANDING_VALUE           NUMBER(18,4)    NOT NULL,
    LATE_AFFECTED_ORDER_VALUE   NUMBER(18,4)    NOT NULL,
    OVERDUE_OUTSTANDING_VALUE   NUMBER(18,4)    NOT NULL,

    -- 6. Shipment metrics (2)
    TOTAL_SHIPMENT_COUNT        NUMBER(9,0)     NOT NULL,
    LATE_SHIPMENT_COUNT         NUMBER(9,0)     NOT NULL,

    -- 7. Delay metrics (4)
    AVG_ORDER_DELAY_DAYS        NUMBER(18,4),
    MAX_ORDER_DELAY_DAYS        NUMBER(9,0),
    AVG_SHIPMENT_DELAY_HOURS    NUMBER(18,4),
    MAX_SHIPMENT_DELAY_HOURS    NUMBER(9,0),

    -- 8. Explainability flags (7)
    HAS_CURRENT_LATE_ORDER      BOOLEAN         NOT NULL,
    HAS_DELIVERED_LATE_ORDER    BOOLEAN         NOT NULL,
    HAS_LATE_ORDER              BOOLEAN         NOT NULL,
    HAS_PARTIAL_FULFILLMENT     BOOLEAN         NOT NULL,
    HAS_UNFULFILLED_ORDER       BOOLEAN         NOT NULL,
    HAS_DELAYED_SHIPMENT        BOOLEAN         NOT NULL,
    IS_IMPACTED                 BOOLEAN         NOT NULL
);

-- ## Post-change validation
-- Table should exist with 34 columns and 0 rows.

-- ## Rollback / manual recovery
-- DROP TABLE IF EXISTS SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT;
