import streamlit as st
import json
import traceback

st.set_page_config(page_title="Agent Diagnostic", layout="wide")
st.title("Agent Call Diagnostic")

from snowflake.snowpark.context import get_active_session
session = get_active_session()

# 1. Session context
st.subheader("1. Session Context")
try:
    ctx = session.sql("""
        SELECT
            CURRENT_USER() AS usr,
            CURRENT_ROLE() AS rl,
            CURRENT_WAREHOUSE() AS wh,
            CURRENT_DATABASE() AS db,
            CURRENT_SCHEMA() AS sch,
            CURRENT_ACCOUNT() AS acct
    """).collect()
    row = ctx[0]
    st.code(f"USER:      {row[0]}\nROLE:      {row[1]}\nWAREHOUSE: {row[2]}\nDATABASE:  {row[3]}\nSCHEMA:    {row[4]}\nACCOUNT:   {row[5]}", language="text")
except Exception as e:
    st.error(f"Context query failed: {e}")

# 2. Agent accessibility
st.subheader("2. Agent Object Check")
try:
    agents = session.sql("SHOW AGENTS IN SCHEMA SUPPLY_CHAIN_DW.GOLD").collect()
    st.write(f"Found {len(agents)} agent(s)")
    for a in agents:
        st.text(f"  - {a[1]}")
except Exception as e:
    st.error(f"SHOW AGENTS failed: {e}")

# 3. Simple SQL test
st.subheader("3. Simple SQL Test")
try:
    r = session.sql("SELECT 'hello' AS test").collect()
    st.success(f"Simple SQL works: {r[0][0]}")
except Exception as e:
    st.error(f"Simple SQL failed: {e}")

# 4. Cortex function test (non-agent)
st.subheader("4. Cortex Non-Agent Test")
try:
    r = session.sql("SELECT SNOWFLAKE.CORTEX.COMPLETE('snowflake-arctic', 'Say hello in 3 words') AS resp").collect()
    st.success(f"CORTEX.COMPLETE works: {r[0][0][:200]}")
except Exception as e:
    st.error(f"CORTEX.COMPLETE failed: {e}")

# 5. DATA_AGENT_RUN with specialist
st.subheader("5. DATA_AGENT_RUN Test")

payload = json.dumps({
    "messages": [
        {
            "role": "user",
            "content": [{"type": "text", "text": "Which routes have the highest delivery delays?"}]
        }
    ]
})
safe_payload = payload.replace("'", "''")

sql_no_thread = (
    f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN("
    f"'SUPPLY_CHAIN_DW.GOLD.LOGISTICS_RISK_AGENT',"
    f"'{safe_payload}'"
    f") AS response"
)

sql_with_thread = (
    f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN("
    f"'SUPPLY_CHAIN_DW.GOLD.LOGISTICS_RISK_AGENT',"
    f"'{safe_payload}',"
    f"TRUE"
    f") AS response"
)

# 5a. Without create_thread_if_not_present
st.markdown("**5a. Without thread creation (2 args):**")
st.code(sql_no_thread[:300] + "...", language="sql")
try:
    rows = session.sql(sql_no_thread).collect()
    raw = rows[0][0]
    st.write(f"Python type: `{type(raw).__name__}`")
    st.write(f"Length: {len(str(raw))}")
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
            if "code" in parsed and "content" not in parsed:
                st.error(f"Error response: {json.dumps(parsed, indent=2)[:1000]}")
            else:
                st.success("Agent returned content successfully!")
                texts = [c.get("text","") for c in parsed.get("content",[]) if c.get("type")=="text" and c.get("text")]
                if texts:
                    st.write(texts[0][:500])
        except json.JSONDecodeError:
            st.warning(f"Raw string (not JSON): {str(raw)[:500]}")
    elif isinstance(raw, dict):
        if "code" in raw and "content" not in raw:
            st.error(f"Error response: {json.dumps(raw, default=str, indent=2)[:1000]}")
        else:
            st.success("Agent returned content successfully (dict)!")
    else:
        st.warning(f"Unexpected type {type(raw).__name__}: {str(raw)[:500]}")
except Exception as e:
    st.error(f"DATA_AGENT_RUN (no thread) failed:\n{traceback.format_exc()}")

# 5b. With create_thread_if_not_present = TRUE
st.markdown("**5b. With thread creation (3 args, TRUE):**")
try:
    rows2 = session.sql(sql_with_thread).collect()
    raw2 = rows2[0][0]
    st.write(f"Python type: `{type(raw2).__name__}`")
    if isinstance(raw2, str):
        try:
            parsed2 = json.loads(raw2)
            if "code" in parsed2 and "content" not in parsed2:
                st.error(f"Error response: {json.dumps(parsed2, indent=2)[:1000]}")
            else:
                st.success("Agent returned content successfully!")
        except json.JSONDecodeError:
            st.warning(f"Raw string: {str(raw2)[:500]}")
    elif isinstance(raw2, dict):
        if "code" in raw2 and "content" not in raw2:
            st.error(f"Error response: {json.dumps(raw2, default=str, indent=2)[:1000]}")
        else:
            st.success("Agent returned content successfully (dict)!")
    else:
        st.warning(f"Unexpected type: {str(raw2)[:500]}")
except Exception as e:
    st.error(f"DATA_AGENT_RUN (with thread) failed:\n{traceback.format_exc()}")

# 6. SP wrapper test
st.subheader("6. SP_INVOKE_AGENT Test")
try:
    sp_rows = session.sql("""
        CALL SUPPLY_CHAIN_DW.GOLD.SP_INVOKE_AGENT(
            'SUPPLY_CHAIN_DW.GOLD.LOGISTICS_RISK_AGENT',
            'Which routes have the highest delivery delays?'
        )
    """).collect()
    sp_raw = sp_rows[0][0]
    st.write(f"Python type: `{type(sp_raw).__name__}`")
    if isinstance(sp_raw, str):
        try:
            sp_parsed = json.loads(sp_raw)
            if "code" in sp_parsed and "content" not in sp_parsed:
                st.error(f"SP Error: {json.dumps(sp_parsed, indent=2)[:1000]}")
            else:
                st.success("SP wrapper returned content successfully!")
        except json.JSONDecodeError:
            st.warning(f"SP raw: {str(sp_raw)[:500]}")
    else:
        st.write(f"SP raw value: {str(sp_raw)[:500]}")
except Exception as e:
    st.error(f"SP_INVOKE_AGENT failed:\n{traceback.format_exc()}")
