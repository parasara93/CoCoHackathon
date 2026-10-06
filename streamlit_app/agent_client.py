"""
agent_client.py — Wrapper for calling Snowflake Cortex Agents via SP_INVOKE_AGENT.
"""
import json
from decimal import Decimal

import streamlit as st


AGENT_MAP = {
    "Procurement Expert": "SUPPLY_CHAIN_DW.GOLD.SUPPLIER_RISK_AGENT",
    "Logistics Expert": "SUPPLY_CHAIN_DW.GOLD.LOGISTICS_RISK_AGENT",
    "Inventory & Plant Expert": "SUPPLY_CHAIN_DW.GOLD.INVENTORY_RISK_AGENT",
    "Plant Fulfillment Expert": "SUPPLY_CHAIN_DW.GOLD.PLANT_FULFILLMENT_AGENT",
    "Customer Impact Expert": "SUPPLY_CHAIN_DW.GOLD.CUSTOMER_IMPACT_AGENT",
    "Overall Resilience Expert": "SUPPLY_CHAIN_DW.GOLD.RESILIENCE_ORCHESTRATOR",
}


def _get_session():
    from snowflake.snowpark.context import get_active_session
    return get_active_session()


def call_agent(expert: str, question: str) -> dict:
    """Call the specialist agent mapped to `expert` with `question`.

    Uses SP_INVOKE_AGENT stored procedure to ensure DATA_AGENT_RUN
    executes in a proper SQL context (EXECUTE AS OWNER), which avoids
    the 399525 internal error seen in warehouse-runtime Streamlit sessions.

    Returns dict with keys: text, tools_used, raw.
    """
    agent_fqn = AGENT_MAP.get(expert)
    if agent_fqn is None:
        if expert in AGENT_MAP.values():
            agent_fqn = expert
        else:
            raise KeyError(f"Unknown expert: {expert}")

    # Escape single quotes in the question for safe SQL embedding.
    safe_question = question.replace("'", "''")

    sql = (
        f"CALL SUPPLY_CHAIN_DW.GOLD.SP_INVOKE_AGENT("
        f"'{agent_fqn}',"
        f"'{safe_question}'"
        f")"
    )

    session = _get_session()

    try:
        session.sql("ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 300").collect()
    except Exception:
        pass

    rows = session.sql(sql).collect()
    raw_val = rows[0][0]

    # Parse the JSON response string.
    if isinstance(raw_val, str):
        try:
            resp = json.loads(raw_val)
        except (json.JSONDecodeError, TypeError):
            return {
                "text": raw_val,
                "tools_used": [],
                "raw": raw_val,
            }
    elif isinstance(raw_val, dict):
        resp = raw_val
    elif raw_val is None:
        return {
            "text": "Agent returned no response.",
            "tools_used": [],
            "raw": None,
        }
    else:
        return {
            "text": str(raw_val),
            "tools_used": [],
            "raw": str(raw_val),
        }

    # Check for error response — show full detail.
    if isinstance(resp, dict) and "code" in resp and "content" not in resp:
        code = resp.get("code", "unknown")
        message = resp.get("message", "Unknown error")
        request_id = resp.get("request_id", "")
        error_detail = f"Agent error [{code}]: {message}"
        if request_id:
            error_detail += f" (request_id: {request_id})"
        return {
            "text": error_detail,
            "tools_used": [],
            "raw": resp,
        }

    # Extract text and tool names from successful response.
    text_parts = []
    tools_used = []
    for item in resp.get("content", []):
        t = item.get("type", "")
        if t == "text" and item.get("text"):
            text_parts.append(item["text"])
        elif t == "tool_use":
            name = (item.get("tool_use") or item).get("name", "")
            if name and name not in ("system_execute_sql", "server_skill", "data_to_chart"):
                tools_used.append(name)
        elif t == "tool_result":
            name = (item.get("tool_result") or item).get("name", "")
            if name and name not in ("system_execute_sql", "server_skill", "data_to_chart"):
                if name not in tools_used:
                    tools_used.append(name)

    return {
        "text": "\n\n".join(text_parts),
        "tools_used": list(dict.fromkeys(tools_used)),
        "raw": resp,
    }


def run_sql(sql: str) -> list[dict]:
    """Execute governed SQL and return list of row-dicts."""
    session = _get_session()
    df = session.sql(sql).to_pandas()
    for col in df.columns:
        if df[col].apply(lambda x: isinstance(x, Decimal)).any():
            df[col] = df[col].apply(lambda x: float(x) if isinstance(x, Decimal) else x)
    return df.to_dict(orient="records")
