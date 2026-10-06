-- =============================================================================
-- V3.19.0 — Create Orchestrator Invocation Procedure for Streamlit
-- =============================================================================
-- Purpose:
--   Provides a stable execution bridge for invoking RESILIENCE_ORCHESTRATOR
--   from Streamlit-in-Snowflake warehouse runtime sessions.
--
--   Direct DATA_AGENT_RUN calls to the orchestrator fail with 399525 from
--   warehouse-runtime Streamlit sessions (specialist agents work fine).
--   This procedure wraps the same working DATA_AGENT_RUN call inside an
--   EXECUTE AS CALLER stored procedure, which provides the execution context
--   the orchestrator requires.
--
-- Usage:
--   CALL SUPPLY_CHAIN_DW.GOLD.SP_INVOKE_RESILIENCE_ORCHESTRATOR(
--       'What are the top three risks that need operational attention?'
--   );
--
-- Notes:
--   * The procedure does not alter the agent response in any way.
--   * It does not call specialist agents, GitHub, or risk-case procedures
--     directly — all tool invocation is handled by the orchestrator itself.
--   * The JSON request body matches the exact structure that succeeds from
--     direct SQL: single user message, create_thread_if_not_present = TRUE.
-- =============================================================================

USE DATABASE SUPPLY_CHAIN_DW;
USE SCHEMA GOLD;

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_DW.GOLD.SP_INVOKE_RESILIENCE_ORCHESTRATOR(
    P_QUESTION VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_PAYLOAD VARCHAR;
    V_RESULT  VARCHAR;
BEGIN
    -- Construct the JSON request body.
    -- Escape backslashes, double quotes, and single quotes in user input.
    V_PAYLOAD := '{"messages":[{"role":"user","content":[{"type":"text","text":"' ||
                 REPLACE(
                     REPLACE(
                         REPLACE(:P_QUESTION, '\\', '\\\\'),
                         '"', '\\"'
                     ),
                     '''', '\\'''
                 ) ||
                 '"}]}]}';

    -- Invoke the orchestrator using the exact pattern that succeeds from direct SQL.
    SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        'SUPPLY_CHAIN_DW.GOLD.RESILIENCE_ORCHESTRATOR',
        :V_PAYLOAD,
        TRUE
    ) INTO :V_RESULT;

    RETURN :V_RESULT;
END;
$$;
