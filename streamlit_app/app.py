from __future__ import annotations

import inspect
from typing import Any, Callable, Dict, List, Optional, Tuple

import streamlit as st

import agent_client
import chart_queries

try:
    from risk_cases import render_risk_cases
except Exception:
    render_risk_cases = None


st.set_page_config(
    page_title="Resilient Supply Chain Control Tower",
    page_icon="SC",
    layout="wide",
)

APP_TITLE = "Resilient Supply Chain Control Tower"
APP_SUBTITLE = (
    "Conversational risk intelligence across suppliers, inventory, fulfillment, "
    "logistics, and customer impact."
)

EXPERTS: Dict[str, Dict[str, Any]] = {
    "Procurement Expert": {
        "agent": "SUPPLY_CHAIN_DW.GOLD.SUPPLIER_RISK_AGENT",
        "description": "Supplier performance, deterioration, sourcing risk, and downstream exposure.",
        "capability_hint": "Ask about supplier risk scores, lead-time deterioration, quality, fill rate, and exposed demand.",
        "suggestions": [
            "Which suppliers are at risk and why?",
            "Which supplier has the highest risk score?",
            "Which suppliers have the worst on-time delivery decline?",
            "How much outstanding order value is exposed to deteriorating suppliers?",
            "Generate a chart ranking suppliers by risk score.",
        ],
    },
    "Inventory & Plant Expert": {
        "agent": "SUPPLY_CHAIN_DW.GOLD.INVENTORY_RISK_AGENT",
        "description": "Plant inventory shortages, safety-stock breaches, reorder pressure, and fulfillment risk.",
        "capability_hint": "Ask about out-of-stock positions, low inventory, critical parts, plant exposure, and reorder risk.",
        "suggestions": [
            "Which parts are below safety stock and at which plants?",
            "Which plant has the most out-of-stock positions?",
            "Show the highest-risk inventory positions.",
            "What outstanding demand is exposed to low inventory?",
            "Generate a chart of below-safety-stock positions by plant.",
        ],
    },
    "Plant Fulfillment Expert": {
        "agent": "SUPPLY_CHAIN_DW.GOLD.PLANT_FULFILLMENT_AGENT",
        "description": "Order backlog, fulfillment performance, late orders, and plant-level outstanding demand.",
        "capability_hint": "Ask about backlog, late orders, fulfillment percentage, outstanding quantity, and plant bottlenecks.",
        "suggestions": [
            "Which plant has the highest order backlog?",
            "Which orders are currently late with the highest outstanding value?",
            "What is the average fulfillment rate by plant?",
            "Show unfulfilled orders at the highest-risk plant.",
            "Generate a chart of backlog by plant.",
        ],
    },
    "Logistics Expert": {
        "agent": "SUPPLY_CHAIN_DW.GOLD.LOGISTICS_RISK_AGENT",
        "description": "Shipment delays, route disruptions, carrier performance, transit variance, and shipping cost.",
        "capability_hint": "Ask about disrupted routes, delayed shipments, carrier performance, route deviations, and shipping cost.",
        "suggestions": [
            "Which routes have the highest delivery delays?",
            "Which carriers have the worst on-time performance?",
            "Show the most disrupted shipments.",
            "What is the total cost of delayed shipments?",
            "Generate a chart of delivery delay by route.",
        ],
    },
    "Customer Impact Expert": {
        "agent": "SUPPLY_CHAIN_DW.GOLD.CUSTOMER_IMPACT_AGENT",
        "description": "Customer disruption impact, late orders, overdue value, fulfillment, and segment exposure.",
        "capability_hint": "Ask which customers are most impacted and how much value is overdue or outstanding.",
        "suggestions": [
            "Which customers are most impacted by supply chain disruptions?",
            "What is the total overdue outstanding value across impacted customers?",
            "Which customer segment has the worst fulfillment rate?",
            "Show customers with the highest outstanding value.",
            "Generate a chart ranking impacted customers by outstanding value.",
        ],
    },
    "Overall Resilience Expert": {
        "agent": "SUPPLY_CHAIN_DW.GOLD.RESILIENCE_INSIGHTS_AGENT",
        "description": "Cross-domain resilience analysis across all five supply-chain risk domains.",
        "capability_hint": (
            "Analyzes cross-domain risks using all specialist agents. "
            "Read-only — risk cases and GitHub issues are created through the Action Agent in Snowsight."
        ),
        "suggestions": [
            "Give me a resilience dashboard summary of the highest-priority risks.",
            "Trace the major risks across supplier, inventory, fulfillment, logistics, and customer impact.",
            "Which suppliers have the most downstream exposure to late orders?",
            "Compare inventory pressure vs fulfillment backlog by plant.",
            "What are the top three risks that need operational attention right now?",
        ],
    },
}


def _safe_rerun():
    if hasattr(st, "rerun"):
        st.rerun()
    else:
        st.experimental_rerun()


def _resolve_agent_callable() -> Callable[..., Any]:
    for name in (
        "call_agent",
        "invoke_agent",
        "ask_agent",
        "run_agent",
        "query_agent",
        "send_message",
    ):
        fn = getattr(agent_client, name, None)
        if callable(fn):
            return fn
    raise AttributeError(
        "No supported agent invocation function was found in agent_client.py. "
        "Expected one of: call_agent, invoke_agent, ask_agent, run_agent, query_agent, send_message."
    )


def _call_agent(agent_name: str, question: str) -> Any:
    fn = _resolve_agent_callable()
    sig = inspect.signature(fn)
    names = list(sig.parameters.keys())

    kwargs: Dict[str, Any] = {}
    for p in names:
        lp = p.lower()
        if lp in {"agent", "agent_name", "agent_fqn"}:
            kwargs[p] = agent_name
        elif lp in {"question", "prompt", "message", "user_message", "query"}:
            kwargs[p] = question

    if len(kwargs) >= 2:
        return fn(**kwargs)

    if len(names) >= 2:
        return fn(agent_name, question)

    if len(names) == 1:
        return fn(question)

    return fn()


def _normalize_agent_response(result: Any) -> Tuple[str, List[str]]:
    if result is None:
        return "No response returned by the agent.", []

    if isinstance(result, str):
        return result, []

    if isinstance(result, dict):
        text = (
            result.get("text")
            or result.get("response")
            or result.get("answer")
            or result.get("message")
            or result.get("content")
        )
        tools = result.get("tools") or result.get("tool_names") or result.get("tools_used") or []
        if isinstance(tools, str):
            tools = [tools]
        if text is not None:
            return str(text), list(tools)

    return str(result), []


def _find_chart_renderer() -> Optional[Callable[..., Any]]:
    for name in (
        "render_chart_for_question",
        "render_chart",
        "build_chart",
        "get_chart",
    ):
        fn = getattr(chart_queries, name, None)
        if callable(fn):
            return fn
    return None


def _render_optional_chart(expert_name: str, question: str) -> None:
    renderer = _find_chart_renderer()
    if renderer is None:
        return

    try:
        sig = inspect.signature(renderer)
        params = list(sig.parameters.keys())
        kwargs: Dict[str, Any] = {}

        for p in params:
            lp = p.lower()
            if lp in {"expert", "expert_name"}:
                kwargs[p] = expert_name
            elif lp in {"question", "prompt", "query"}:
                kwargs[p] = question

        if kwargs:
            chart = renderer(**kwargs)
        elif len(params) >= 2:
            chart = renderer(expert_name, question)
        elif len(params) == 1:
            chart = renderer(question)
        else:
            chart = renderer()

        if chart is None:
            return

        if hasattr(chart, "to_dict") or chart.__class__.__module__.startswith("altair"):
            st.altair_chart(chart)
        elif hasattr(chart, "figure"):
            st.pyplot(chart.figure)
    except Exception:
        return


def _init_state() -> None:
    defaults = {
        "messages": [],
        "conversation_started": False,
        "selected_suggestion": None,
        "active_expert": "Procurement Expert",
        "show_risk_cases": False,
    }
    for key, value in defaults.items():
        if key not in st.session_state:
            st.session_state[key] = value


def _reset_conversation() -> None:
    st.session_state.messages = []
    st.session_state.conversation_started = False
    st.session_state.selected_suggestion = None


def _on_expert_change() -> None:
    _reset_conversation()


def _render_header() -> None:
    st.title(APP_TITLE)
    st.caption(APP_SUBTITLE)


def _render_expert_selector() -> str:
    col1, col2 = st.columns([4, 1])

    with col1:
        expert = st.selectbox(
            "Choose an expert",
            list(EXPERTS.keys()),
            key="active_expert",
            on_change=_on_expert_change,
        )

    with col2:
        st.write("")
        st.write("")
        if st.button("Start over"):
            _reset_conversation()
            _safe_rerun()

    cfg = EXPERTS[expert]
    st.markdown(f"**{cfg['description']}**")
    st.caption(cfg["capability_hint"])

    if expert == "Overall Resilience Expert":
        st.info(
            "This agent provides read-only cross-domain analysis. "
            "To create risk cases or GitHub issues, use the Resilience Action Agent in Snowsight."
        )

    return expert


def _render_suggestions(expert_name: str) -> None:
    if st.session_state.conversation_started:
        return

    cfg = EXPERTS[expert_name]
    st.subheader("Suggested questions")
    st.caption("Select a question, then click Ask. Suggestions disappear once the conversation starts.")

    suggestions: List[str] = cfg["suggestions"]

    for idx, suggestion in enumerate(suggestions):
        is_selected = st.session_state.selected_suggestion == suggestion
        label = f"{'> ' if is_selected else ''}{suggestion}"
        if st.button(
            label,
            key=f"suggestion_{expert_name}_{idx}",
        ):
            st.session_state.selected_suggestion = suggestion
            _safe_rerun()

    if st.session_state.selected_suggestion:
        st.text_area(
            "Selected question",
            value=st.session_state.selected_suggestion,
            height=80,
            disabled=True,
        )

        ask_col, clear_col = st.columns([1, 1])

        with ask_col:
            if st.button("Ask"):
                question = st.session_state.selected_suggestion
                st.session_state.conversation_started = True
                st.session_state.selected_suggestion = None
                st.session_state.pending_question = question
                _safe_rerun()

        with clear_col:
            if st.button("Choose another"):
                st.session_state.selected_suggestion = None
                _safe_rerun()


def _render_message_history() -> None:
    for msg in st.session_state.messages:
        role = msg.get("role", "assistant")
        if role == "user":
            st.markdown(f"**You:** {msg.get('content', '')}")
        else:
            st.markdown(f"**Expert:** {msg.get('content', '')}")
            tools = msg.get("tools") or []
            if tools:
                st.caption("Tools: " + ", ".join(tools))


def _process_question(expert_name: str, question: str) -> None:
    if not question or not question.strip():
        return

    question = question.strip()
    st.session_state.conversation_started = True
    st.session_state.messages.append({"role": "user", "content": question})

    st.markdown(f"**You:** {question}")

    _render_optional_chart(expert_name, question)

    with st.spinner(f"Consulting the {expert_name}..."):
        try:
            raw = _call_agent(EXPERTS[expert_name]["agent"], question)
            answer, tools = _normalize_agent_response(raw)
        except Exception as exc:
            answer = (
                "I couldn't complete the agent request. "
                f"Details: {exc}"
            )
            tools = []

    st.markdown(f"**Expert:** {answer}")
    if tools:
        st.caption("Tools: " + ", ".join(tools))

    st.session_state.messages.append(
        {
            "role": "assistant",
            "content": answer,
            "tools": tools,
        }
    )


def _render_chat_input(expert_name: str) -> None:
    st.markdown("---")
    input_col, btn_col = st.columns([5, 1])

    with input_col:
        question = st.text_input(
            f"Ask the {expert_name}",
            key="user_question_input",
            label_visibility="collapsed",
            placeholder=f"Ask the {expert_name}...",
        )

    with btn_col:
        submitted = st.button("Send")

    if submitted and question:
        st.session_state.conversation_started = True
        _process_question(expert_name, question)


def _render_risk_case_panel() -> None:
    if render_risk_cases is None:
        return

    with st.expander("Risk Cases", expanded=False):
        st.caption(
            "Governed cases persisted in SUPPLY_CHAIN_DW.CONTROL.RISK_CASE. "
            "Create cases through the Overall Resilience Expert, not by direct UI insert."
        )
        render_risk_cases()


def main() -> None:
    _init_state()
    _render_header()

    expert_name = _render_expert_selector()

    _render_risk_case_panel()

    _render_suggestions(expert_name)

    _render_message_history()

    pending = st.session_state.pop("pending_question", None)
    if pending:
        _process_question(expert_name, pending)

    _render_chat_input(expert_name)


if __name__ == "__main__":
    main()
