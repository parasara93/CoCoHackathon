-- =============================================================================
-- V3.18.0 — Create Risk Case Procedure
-- =============================================================================
--
-- Change purpose
--   Create the governed action used by agents/tools to create risk cases.
--
-- Affected object
--   SUPPLY_CHAIN_DW.CONTROL.SP_CREATE_RISK_CASE
--
-- Backend table
--   SUPPLY_CHAIN_DW.CONTROL.RISK_CASE
--
-- Preconditions
--   V3.17.0__create_risk_case_table.sql applied.
-- =============================================================================

USE DATABASE SUPPLY_CHAIN_DW;
USE SCHEMA CONTROL;


CREATE OR REPLACE PROCEDURE
SUPPLY_CHAIN_DW.CONTROL.SP_CREATE_RISK_CASE(
    P_ENTITY_TYPE         VARCHAR,
    P_ENTITY_ID           VARCHAR,
    P_RISK_TYPE           VARCHAR,
    P_SEVERITY            VARCHAR,
    P_SUMMARY             VARCHAR,
    P_RECOMMENDED_ACTION  VARCHAR,
    P_SOURCE_AGENT        VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_CASE_ID   VARCHAR;
    V_SEVERITY  VARCHAR;
BEGIN

    -- -------------------------------------------------------------------------
    -- Basic input validation
    -- -------------------------------------------------------------------------

    IF (
        P_ENTITY_TYPE IS NULL
        OR TRIM(P_ENTITY_TYPE) = ''
        OR P_ENTITY_ID IS NULL
        OR TRIM(P_ENTITY_ID) = ''
        OR P_RISK_TYPE IS NULL
        OR TRIM(P_RISK_TYPE) = ''
        OR P_SEVERITY IS NULL
        OR TRIM(P_SEVERITY) = ''
        OR P_SUMMARY IS NULL
        OR TRIM(P_SUMMARY) = ''
    ) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'ENTITY_TYPE, ENTITY_ID, RISK_TYPE, SEVERITY and SUMMARY are required'
        );
    END IF;


    V_SEVERITY := UPPER(TRIM(P_SEVERITY));


    IF (V_SEVERITY NOT IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')) THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', 'SEVERITY must be LOW, MEDIUM, HIGH or CRITICAL'
        );
    END IF;


    -- -------------------------------------------------------------------------
    -- Human-readable case identifier with UUID-backed uniqueness
    -- Example: RISK-8C12A34F56B7
    -- -------------------------------------------------------------------------

    V_CASE_ID :=
        'RISK-' ||
        LEFT(
            REPLACE(UUID_STRING(), '-', ''),
            12
        );


    -- -------------------------------------------------------------------------
    -- Controlled insert
    -- -------------------------------------------------------------------------

    INSERT INTO SUPPLY_CHAIN_DW.CONTROL.RISK_CASE (
        CASE_ID,
        ENTITY_TYPE,
        ENTITY_ID,
        RISK_TYPE,
        SEVERITY,
        SUMMARY,
        RECOMMENDED_ACTION,
        STATUS,
        SOURCE_AGENT,
        CREATED_BY,
        CREATED_AT,
        UPDATED_AT
    )
    VALUES (
        :V_CASE_ID,
        UPPER(TRIM(P_ENTITY_TYPE)),
        TRIM(P_ENTITY_ID),
        UPPER(TRIM(P_RISK_TYPE)),
        :V_SEVERITY,
        TRIM(P_SUMMARY),
        NULLIF(TRIM(P_RECOMMENDED_ACTION), ''),
        'OPEN',
        NULLIF(TRIM(P_SOURCE_AGENT), ''),
        CURRENT_USER(),
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP()
    );


    RETURN OBJECT_CONSTRUCT(
        'status', 'SUCCESS',
        'case_id', V_CASE_ID,
        'entity_type', UPPER(TRIM(P_ENTITY_TYPE)),
        'entity_id', TRIM(P_ENTITY_ID),
        'risk_type', UPPER(TRIM(P_RISK_TYPE)),
        'severity', V_SEVERITY,
        'case_status', 'OPEN'
    );


EXCEPTION
    WHEN OTHER THEN
        RETURN OBJECT_CONSTRUCT(
            'status', 'FAILED',
            'error', SQLERRM
        );
END;
$$;


-- =============================================================================
-- Post-change validation
-- =============================================================================

DESCRIBE PROCEDURE
SUPPLY_CHAIN_DW.CONTROL.SP_CREATE_RISK_CASE(
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR
);


-- =============================================================================
-- Manual smoke test — intentionally not executed by migration
-- =============================================================================
--
-- CALL SUPPLY_CHAIN_DW.CONTROL.SP_CREATE_RISK_CASE(
--     'ROUTE',
--     'RTE-000036',
--     'LOGISTICS_DISRUPTION',
--     'HIGH',
--     'Route shows elevated downstream delivery risk.',
--     'Review carrier routing and identify alternate route capacity.',
--     'RESILIENCE_ORCHESTRATOR'
-- );
--
-- SELECT *
-- FROM SUPPLY_CHAIN_DW.CONTROL.RISK_CASE
-- ORDER BY CREATED_AT DESC;
--
-- =============================================================================


-- =============================================================================
-- Rollback / manual recovery
-- =============================================================================
-- DROP PROCEDURE IF EXISTS
-- SUPPLY_CHAIN_DW.CONTROL.SP_CREATE_RISK_CASE(
--     VARCHAR,
--     VARCHAR,
--     VARCHAR,
--     VARCHAR,
--     VARCHAR,
--     VARCHAR,
--     VARCHAR
-- );
-- =============================================================================
