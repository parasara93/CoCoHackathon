from __future__ import annotations

from decimal import Decimal
from typing import Any, Callable, Optional

import pandas as pd
import streamlit as st

import agent_client


RISK_CASE_SQL = """
SELECT
    CASE_ID,
    ENTITY_TYPE,
    ENTITY_ID,
    RISK_TYPE,
    SEVERITY,
    STATUS,
    SUMMARY,
    RECOMMENDED_ACTION,
    SOURCE_AGENT,
    CREATED_BY,
    CREATED_AT,
    UPDATED_AT
FROM SUPPLY_CHAIN_DW.CONTROL.RISK_CASE
ORDER BY CREATED_AT DESC
"""


def _resolve_sql_runner() -> Optional[Callable[[str], Any]]:
    """
    Reuse the existing Snowflake connection/helper from agent_client.py.
    Supports common helper names so this module does not force a rewrite
    of the already-working connection layer.
    """
    for name in (
        "run_sql",
        "execute_sql",
        "query_sql",
        "fetch_dataframe",
        "sql_to_dataframe",
    ):
        fn = getattr(agent_client, name, None)
        if callable(fn):
            return fn
    return None


def _to_dataframe(result: Any) -> pd.DataFrame:
    if result is None:
        return pd.DataFrame()

    if isinstance(result, pd.DataFrame):
        return result.copy()

    if hasattr(result, "to_pandas") and callable(result.to_pandas):
        return result.to_pandas()

    if isinstance(result, list):
        if not result:
            return pd.DataFrame()
        if isinstance(result[0], dict):
            return pd.DataFrame(result)

    if isinstance(result, dict):
        return pd.DataFrame([result])

    try:
        return pd.DataFrame(result)
    except Exception:
        return pd.DataFrame()


def _normalize_numeric_types(df: pd.DataFrame) -> pd.DataFrame:
    """
    Avoid Streamlit/Arrow/Altair issues with Snowflake Decimal values.
    """
    for col in df.columns:
        if df[col].map(lambda x: isinstance(x, Decimal)).any():
            df[col] = df[col].map(
                lambda x: float(x) if isinstance(x, Decimal) else x
            )
    return df


def load_risk_cases() -> pd.DataFrame:
    runner = _resolve_sql_runner()
    if runner is None:
        raise RuntimeError(
            "risk_cases.py could not find a SQL helper in agent_client.py. "
            "Expose one of: run_sql, execute_sql, query_sql, fetch_dataframe, sql_to_dataframe."
        )

    result = runner(RISK_CASE_SQL)
    return _normalize_numeric_types(_to_dataframe(result))


def render_risk_cases() -> None:
    try:
        df = load_risk_cases()
    except Exception as exc:
        st.warning(f"Risk cases could not be loaded: {exc}")
        return

    if df.empty:
        st.info(
            "No risk cases have been created yet. "
            "Use the Overall Resilience Expert and explicitly ask it to create a risk case."
        )
        return

    # Normalize Snowflake uppercase column names without assuming connector behavior.
    df.columns = [str(c).upper() for c in df.columns]

    filter_col1, filter_col2 = st.columns(2)

    statuses = ["ALL"]
    if "STATUS" in df.columns:
        statuses += sorted(
            str(v) for v in df["STATUS"].dropna().unique()
        )

    severities = ["ALL"]
    if "SEVERITY" in df.columns:
        preferred = ["CRITICAL", "HIGH", "MEDIUM", "LOW"]
        present = {str(v) for v in df["SEVERITY"].dropna().unique()}
        severities += [v for v in preferred if v in present]
        severities += sorted(present - set(preferred))

    with filter_col1:
        status = st.selectbox("Status", statuses, key="risk_case_status_filter")

    with filter_col2:
        severity = st.selectbox(
            "Severity",
            severities,
            key="risk_case_severity_filter",
        )

    filtered = df.copy()

    if status != "ALL" and "STATUS" in filtered.columns:
        filtered = filtered[filtered["STATUS"].astype(str) == status]

    if severity != "ALL" and "SEVERITY" in filtered.columns:
        filtered = filtered[filtered["SEVERITY"].astype(str) == severity]

    display_cols = [
        c
        for c in [
            "CASE_ID",
            "ENTITY_TYPE",
            "ENTITY_ID",
            "RISK_TYPE",
            "SEVERITY",
            "STATUS",
            "SUMMARY",
            "CREATED_AT",
        ]
        if c in filtered.columns
    ]

    st.dataframe(
        filtered[display_cols],
    )

    st.caption(f"{len(filtered)} case(s) shown")
