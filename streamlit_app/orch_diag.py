import streamlit as st
import json
import time
import traceback

st.set_page_config(page_title="Orchestrator Diagnostic", layout="wide")
st.title("Orchestrator Component Diagnostic")

from snowflake.snowpark.context import get_active_session
session = get_active_session()

QUESTION = "Which routes have the highest delivery delays?"
PAYLOAD = json.dumps({"messages":[{"role":"user","content":[{"type":"text","text":QUESTION}]}]})
SAFE_PAYLOAD = PAYLOAD.replace("'", "''")

AGENTS = {
    "1. No tools (instructions only)": "SUPPLY_CHAIN_DW.GOLD.ORCH_DIAG_1",
    "2. One agent_toolset (logistics)": "SUPPLY_CHAIN_DW.GOLD.ORCH_DIAG_2",
    "3. All 5 agent_toolsets": "SUPPLY_CHAIN_DW.GOLD.ORCH_DIAG_3",
    "4. All toolsets + create_risk_case": "SUPPLY_CHAIN_DW.GOLD.ORCH_DIAG_4",
    "5. Production orchestrator": "SUPPLY_CHAIN_DW.GOLD.RESILIENCE_ORCHESTRATOR",
}

for label, agent_fqn in AGENTS.items():
    st.subheader(label)
    st.caption(agent_fqn)
    sql = f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('{agent_fqn}','{SAFE_PAYLOAD}',TRUE) AS response"
    try:
        t0 = time.time()
        rows = session.sql(sql).collect()
        elapsed = time.time() - t0
        raw = rows[0][0]
        st.write(f"Elapsed: {elapsed:.1f}s | Type: `{type(raw).__name__}` | Length: {len(str(raw))}")

        if isinstance(raw, str):
            try:
                parsed = json.loads(raw)
            except Exception:
                parsed = None
                st.warning(f"Not JSON: {raw[:300]}")
        elif isinstance(raw, dict):
            parsed = raw
        else:
            parsed = None
            st.warning(f"Unexpected: {str(raw)[:300]}")

        if parsed:
            if "code" in parsed and "content" not in parsed:
                st.error(f"ERROR [{parsed.get('code')}]: {parsed.get('message')} (request_id: {parsed.get('request_id','')})")
            else:
                texts = [c.get("text","") for c in parsed.get("content",[]) if c.get("type")=="text" and c.get("text")]
                if texts:
                    st.success(f"OK - {len(texts)} text block(s)")
                    st.text(texts[0][:300])
                else:
                    st.success("OK - response has content but no text blocks")
    except Exception as e:
        st.error(f"Exception: {traceback.format_exc()}")
    st.markdown("---")
