"""
agent_client.py — Wrapper for calling Snowflake Cortex Agents via DATA_AGENT_RUN.
"""
import json
from decimal import Decimal
import snowflake.connector


AGENT_MAP = {
    "Procurement Expert": "SUPPLY_CHAIN_DW.GOLD.SUPPLIER_RISK_AGENT",
    "Logistics Expert": "SUPPLY_CHAIN_DW.GOLD.LOGISTICS_RISK_AGENT",
    "Inventory & Plant Expert": "SUPPLY_CHAIN_DW.GOLD.PLANT_FULFILLMENT_AGENT",
    "Customer Impact Expert": "SUPPLY_CHAIN_DW.GOLD.CUSTOMER_IMPACT_AGENT",
    "Overall Resilience Expert": "SUPPLY_CHAIN_DW.GOLD.RESILIENCE_ORCHESTRATOR",
}


def get_snowflake_connection():
    return snowflake.connector.connect(connection_name="CONN")


def call_agent(expert: str, question: str, conn=None) -> dict:
    """Call the specialist agent mapped to `expert` with `question`.

    Returns dict with keys: text, tools_used, raw.
    """
    agent_fqn = AGENT_MAP[expert]
    payload = json.dumps({
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": question}],
            }
        ]
    })

    sql = f"""
    SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        '{agent_fqn}',
        $${payload}$$,
        TRUE
    ) AS response
    """

    close_conn = False
    if conn is None:
        conn = get_snowflake_connection()
        close_conn = True

    try:
        cur = conn.cursor()
        cur.execute(sql)
        raw_str = cur.fetchone()[0]
        cur.close()
    finally:
        if close_conn:
            conn.close()

    resp = json.loads(raw_str) if isinstance(raw_str, str) else raw_str

    # Check for error response
    if "code" in resp and "message" in resp and "content" not in resp:
        return {
            "text": f"Agent error: {resp.get('message', 'Unknown error')}",
            "tools_used": [],
            "raw": resp,
        }

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


def run_sql(sql: str, conn=None) -> list[dict]:
    """Execute governed SQL and return list of row-dicts."""
    close_conn = False
    if conn is None:
        conn = get_snowflake_connection()
        close_conn = True

    try:
        cur = conn.cursor()
        cur.execute(sql)
        cols = [desc[0] for desc in cur.description]
        rows = [
            {c: float(v) if isinstance(v, Decimal) else v for c, v in zip(cols, row)}
            for row in cur.fetchall()
        ]
        cur.close()
    finally:
        if close_conn:
            conn.close()

    return rows
