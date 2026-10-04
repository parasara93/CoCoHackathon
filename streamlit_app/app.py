"""
Resilient Supply Chain Control Tower — Expert Chat Interface
"""
import streamlit as st
import pandas as pd
import altair as alt
from agent_client import call_agent, run_sql, get_snowflake_connection
from chart_queries import CHART_QUERIES, detect_chart_intent

st.set_page_config(
    page_title="Supply Chain Control Tower",
    page_icon="SC",
    layout="wide",
)

EXPERTS = [
    "Overall Resilience Expert",
    "Procurement Expert",
    "Logistics Expert",
    "Inventory & Plant Expert",
    "Customer Impact Expert",
]

SPECIALISTS = [
    "Procurement Expert",
    "Logistics Expert",
    "Inventory & Plant Expert",
    "Customer Impact Expert",
]

EXPERT_SUBTITLES = {
    "Overall Resilience Expert": "Cross-domain synthesis",
    "Procurement Expert": "Supplier risk & landed cost",
    "Logistics Expert": "Routes, carriers & delays",
    "Inventory & Plant Expert": "Inventory pressure & fulfillment",
    "Customer Impact Expert": "Customer exposure & service impact",
}

SUGGESTED_QUESTIONS = {
    "Procurement Expert": [
        "Which suppliers are showing the strongest deterioration?",
        "Which supplier has the highest downstream exposure?",
        "Generate a chart ranking suppliers by risk score.",
        "Generate a chart comparing supplier OTD and fill rate.",
        "Which supplier-part combinations have the highest estimated landed cost?",
    ],
    "Logistics Expert": [
        "Which routes are causing the largest delays?",
        "Which carriers have the weakest on-time performance?",
        "Generate a chart of delayed shipments by route.",
        "Generate a chart comparing route delay and shipping cost.",
        "Which routes show the most disruption events?",
    ],
    "Inventory & Plant Expert": [
        "Which plants have the highest inventory pressure?",
        "Which parts have the lowest days of demand coverage?",
        "Generate a chart of below-safety-stock positions by plant.",
        "Generate a chart of Days of Demand Coverage by plant.",
        "Which plants combine inventory pressure and fulfillment backlog?",
    ],
    "Customer Impact Expert": [
        "Which customers are most impacted?",
        "Which customers have the highest outstanding value?",
        "Generate a chart ranking customers by outstanding value.",
        "Generate a chart comparing fulfillment percentage across customers.",
        "Which customers have the most currently late orders?",
    ],
    "Overall Resilience Expert": [
        "What are the biggest supply-chain risks right now?",
        "Which area should we prioritize first?",
        "Summarize supplier, inventory, logistics, and customer risk.",
        "Generate a chart showing the top risks across domains.",
        "What evidence supports the highest-priority issue?",
    ],
}


def render_chart(chart_key: str, conn) -> alt.Chart | None:
    spec = CHART_QUERIES.get(chart_key)
    if not spec:
        return None

    rows = run_sql(spec["sql"], conn=conn)
    if not rows:
        return None

    df = pd.DataFrame(rows)
    ct = spec["chart_type"]
    title = spec["title"]

    if ct == "horizontal_bar":
        chart = (
            alt.Chart(df, title=title)
            .mark_bar()
            .encode(
                x=alt.X(spec["x"], type="quantitative"),
                y=alt.Y(spec["y"], type="nominal", sort="-x"),
                color=alt.Color(spec.get("color", spec["y"]), type="nominal") if spec.get("color") else alt.value("#4C78A8"),
                tooltip=list(df.columns),
            )
            .properties(height=max(len(df) * 22, 200))
        )
    elif ct == "bar":
        chart = (
            alt.Chart(df, title=title)
            .mark_bar()
            .encode(
                x=alt.X(spec["x"], type="nominal", sort=None),
                y=alt.Y(spec["y"], type="quantitative"),
                color=alt.Color(spec.get("color", spec["x"]), type="nominal") if spec.get("color") else alt.value("#4C78A8"),
                tooltip=list(df.columns),
            )
            .properties(height=350)
        )
    elif ct == "scatter":
        enc = {
            "x": alt.X(spec["x"], type="quantitative"),
            "y": alt.Y(spec["y"], type="quantitative"),
            "tooltip": list(df.columns),
        }
        if spec.get("color"):
            enc["color"] = alt.Color(spec["color"], type="nominal")
        chart = alt.Chart(df, title=title).mark_circle(size=80).encode(**enc).properties(height=400)
    else:
        chart = (
            alt.Chart(df, title=title)
            .mark_bar()
            .encode(
                x=alt.X(list(df.columns)[0], type="nominal"),
                y=alt.Y(list(df.columns)[1], type="quantitative"),
                tooltip=list(df.columns),
            )
            .properties(height=350)
        )

    return chart


def init_session_state():
    if "messages" not in st.session_state:
        st.session_state.messages = []
    if "expert" not in st.session_state:
        st.session_state.expert = EXPERTS[0]
    if "conn" not in st.session_state:
        st.session_state.conn = None
    if "prefill" not in st.session_state:
        st.session_state.prefill = ""


def get_conn():
    if st.session_state.conn is None:
        st.session_state.conn = get_snowflake_connection()
    return st.session_state.conn


def process_question(question: str):
    expert = st.session_state.expert
    st.session_state.messages.append({"role": "user", "content": question})

    chart_key = detect_chart_intent(question, expert)

    with st.chat_message("assistant"):
        if chart_key:
            with st.spinner("Generating chart from governed data..."):
                chart = render_chart(chart_key, get_conn())
            title = CHART_QUERIES[chart_key]["title"]
            st.markdown(f"**{title}**")
            if chart:
                st.altair_chart(chart, width="stretch")
                msg_content = f"**{title}**\n\n*(Chart rendered from governed Gold data)*"
            else:
                st.warning("No data returned for this chart.")
                msg_content = f"Requested chart: {title} -- no data."

            with st.spinner("Getting expert analysis..."):
                result = call_agent(expert, question, conn=get_conn())
            if result["text"]:
                st.markdown(result["text"])
                msg_content += f"\n\n{result['text']}"
            if result["tools_used"]:
                st.caption(f"Tools: {', '.join(result['tools_used'])}")

            st.session_state.messages.append({
                "role": "assistant",
                "content": msg_content,
                "chart_key": chart_key,
                "tools": result.get("tools_used", []),
            })
        else:
            with st.spinner(f"Consulting {expert}..."):
                result = call_agent(expert, question, conn=get_conn())
            st.markdown(result["text"])
            if result["tools_used"]:
                st.caption(f"Tools: {', '.join(result['tools_used'])}")

            st.session_state.messages.append({
                "role": "assistant",
                "content": result["text"],
                "tools": result.get("tools_used", []),
            })


def main():
    init_session_state()

    st.markdown(
        "<h2 style='margin-bottom:0'>Resilient Supply Chain Control Tower</h2>"
        "<p style='color:gray;margin-top:0'>Expert Chat Interface</p>",
        unsafe_allow_html=True,
    )

    # --- Expert hierarchy nav ---
    selected = st.session_state.expert

    def _select(name):
        if name != st.session_state.expert:
            st.session_state.expert = name
            st.session_state.messages = []
            st.session_state.prefill = ""
            st.rerun()

    # Orchestrator row
    orch = "Overall Resilience Expert"
    if selected == orch:
        st.markdown(
            "<p style='color:#e5e7eb; font-weight:600; font-size:1.05rem; margin:0; "
            "border-bottom:2px solid #f87171; display:inline-block; padding-bottom:2px'>"
            "Overall Resilience Expert</p>"
            "<span style='color:#9ca3af; font-size:0.85rem; margin-left:10px'>Cross-domain synthesis</span>",
            unsafe_allow_html=True,
        )
    else:
        if st.button("Overall Resilience Expert  /  Cross-domain synthesis", key="nav_orch", type="tertiary"):
            _select(orch)

    # Specialist row — always show full name with "Expert"
    spec_cols = st.columns(4)
    for i, name in enumerate(SPECIALISTS):
        with spec_cols[i]:
            if selected == name:
                st.markdown(
                    f"<p style='color:#e5e7eb; font-weight:600; font-size:0.93rem; margin:0; "
                    f"border-bottom:2px solid #f87171; display:inline-block; padding-bottom:2px'>"
                    f"{name}</p>",
                    unsafe_allow_html=True,
                )
            else:
                if st.button(name, key=f"nav_spec_{i}", type="tertiary"):
                    _select(name)

    st.markdown("")

    # --- Single chat composer (form): always visible, above suggestions ---
    with st.form("chat_form", clear_on_submit=True, border=False):
        user_input = st.text_input(
            f"Ask the {selected}...",
            value=st.session_state.prefill,
            placeholder=f"Ask the {selected}...",
            label_visibility="collapsed",
        )
        send = st.form_submit_button("Send")

    # --- Suggested questions (only when no chat history) ---
    if not st.session_state.messages:
        st.markdown(
            "<span style='color:#9ca3af; font-size:0.85rem'>Suggested questions</span>",
            unsafe_allow_html=True,
        )
        suggestions = SUGGESTED_QUESTIONS[selected]
        for i, q in enumerate(suggestions):
            if st.button(f"\u2192  {q}", key=f"suggest_{i}", type="tertiary"):
                st.session_state.prefill = q
                st.rerun()

    st.markdown("---")

    # --- Process submission (single path) ---
    if send and user_input and user_input.strip():
        st.session_state.prefill = ""
        question = user_input.strip()
        with st.chat_message("user"):
            st.markdown(question)
        process_question(question)
        st.rerun()

    # --- Chat history ---
    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])
            if msg.get("chart_key"):
                chart = render_chart(msg["chart_key"], get_conn())
                if chart:
                    st.altair_chart(chart, width="stretch")
            if msg.get("tools"):
                st.caption(f"Tools: {', '.join(msg['tools'])}")


if __name__ == "__main__":
    main()
