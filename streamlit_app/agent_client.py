"""
agent_client.py — Wrapper for calling Snowflake Cortex Agents via DATA_AGENT_RUN.

All agents are invoked directly. The Overall Resilience Expert maps to
RESILIENCE_INSIGHTS_AGENT (read-only, no MCP/action tools) which works
from warehouse-runtime Streamlit sessions without the SP bridge.
"""
import json
from decimal import Decimal


AGENT_MAP = {
    "Procurement Expert": "SUPPLY_CHAIN_DW.GOLD.SUPPLIER_RISK_AGENT",
    "Logistics Expert": "SUPPLY_CHAIN_DW.GOLD.LOGISTICS_RISK_AGENT",
    "Inventory & Plant Expert": "SUPPLY_CHAIN_DW.GOLD.INVENTORY_RISK_AGENT",
    "Plant Fulfillment Expert": "SUPPLY_CHAIN_DW.GOLD.PLANT_FULFILLMENT_AGENT",
    "Customer Impact Expert": "SUPPLY_CHAIN_DW.GOLD.CUSTOMER_IMPACT_AGENT",
    "Overall Resilience Expert": "SUPPLY_CHAIN_DW.GOLD.RESILIENCE_INSIGHTS_AGENT",
}


def _get_session():
    from snowflake.snowpark.context import get_active_session
    return get_active_session()


def _parse_response(raw_val) -> dict:
    """Parse DATA_AGENT_RUN response into {text, tools_used, raw}."""
    if isinstance(raw_val, str):
        try:
            resp = json.loads(raw_val)
        except (json.JSONDecodeError, TypeError):
            return {"text": raw_val, "tools_used": [], "raw": raw_val}
    elif isinstance(raw_val, dict):
        resp = raw_val
    elif raw_val is None:
        return {"text": "Agent returned no response.", "tools_used": [], "raw": None}
    else:
        return {"text": str(raw_val), "tools_used": [], "raw": str(raw_val)}

    if isinstance(resp, dict) and "code" in resp and "content" not in resp:
        code = resp.get("code", "unknown")
        message = resp.get("message", "Unknown error")
        request_id = resp.get("request_id", "")
        error_detail = f"Agent error [{code}]: {message}"
        if request_id:
            error_detail += f" (request_id: {request_id})"
        return {"text": error_detail, "tools_used": [], "raw": resp}

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


def call_agent(expert: str, question: str) -> dict:
    """Call the agent mapped to `expert` with `question`."""
    agent_fqn = AGENT_MAP.get(expert)
    if agent_fqn is None:
        if expert in AGENT_MAP.values():
            agent_fqn = expert
        else:
            raise KeyError(f"Unknown expert: {expert}")

    payload = json.dumps({
        "messages": [
            {"role": "user", "content": [{"type": "text", "text": question}]}
        ]
    })
    safe_payload = payload.replace("'", "''")

    sql = (
        f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN("
        f"'{agent_fqn}',"
        f"'{safe_payload}',"
        f"TRUE"
        f") AS response"
    )

    session = _get_session()

    try:
        session.sql("ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 300").collect()
    except Exception:
        pass

    rows = session.sql(sql).collect()
    return _parse_response(rows[0][0])


def run_sql(sql: str) -> list[dict]:
    """Execute governed SQL and return list of row-dicts."""
    session = _get_session()
    df = session.sql(sql).to_pandas()
    for col in df.columns:
        if df[col].apply(lambda x: isinstance(x, Decimal)).any():
            df[col] = df[col].apply(lambda x: float(x) if isinstance(x, Decimal) else x)
    return df.to_dict(orient="records")
