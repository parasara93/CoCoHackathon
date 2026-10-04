"""
chart_queries.py — Governed deterministic SQL for chart generation.
All queries run against Gold marts / semantic views.
"""

CHART_QUERIES = {
    # ── Procurement / Supplier Risk ──────────────────────────────
    "supplier_risk_score_ranking": {
        "title": "Suppliers Ranked by Latest Risk Score",
        "sql": """
            SELECT supplier_name, latest_risk_score, supplier_tier,
                   CASE WHEN is_supplier_at_risk THEN 'At Risk' ELSE 'OK' END AS risk_status
            FROM SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK
            ORDER BY latest_risk_score DESC
        """,
        "chart_type": "horizontal_bar",
        "x": "LATEST_RISK_SCORE",
        "y": "SUPPLIER_NAME",
        "color": "RISK_STATUS",
    },
    "supplier_otd_vs_fill": {
        "title": "Supplier OTD % vs Fill Rate %",
        "sql": """
            SELECT supplier_name, latest_on_time_delivery_pct AS otd_pct,
                   latest_fill_rate_pct AS fill_rate_pct, supplier_tier
            FROM SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK
            ORDER BY otd_pct
        """,
        "chart_type": "scatter",
        "x": "OTD_PCT",
        "y": "FILL_RATE_PCT",
        "color": "SUPPLIER_TIER",
        "tooltip": "SUPPLIER_NAME",
    },
    "supplier_outstanding_exposure": {
        "title": "Suppliers by Downstream Outstanding Exposure ($)",
        "sql": """
            SELECT supplier_name, active_exposed_outstanding_value AS exposure_value,
                   supplier_tier
            FROM SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK
            WHERE active_exposed_outstanding_value > 0
            ORDER BY exposure_value DESC
        """,
        "chart_type": "horizontal_bar",
        "x": "EXPOSURE_VALUE",
        "y": "SUPPLIER_NAME",
        "color": "SUPPLIER_TIER",
    },
    "landed_cost_top": {
        "title": "Top 20 Supplier-Part by Estimated Landed Unit Cost",
        "sql": """
            SELECT supplier_id || ' / ' || part_id AS supplier_part,
                   supplier_unit_cost, allocated_freight_per_unit,
                   estimated_landed_unit_cost_qty_alloc AS landed_cost
            FROM SUPPLY_CHAIN_DW.GOLD.MART_LANDED_COST
            ORDER BY landed_cost DESC LIMIT 20
        """,
        "chart_type": "horizontal_bar",
        "x": "LANDED_COST",
        "y": "SUPPLIER_PART",
    },

    # ── Logistics ────────────────────────────────────────────────
    "route_delay_ranking": {
        "title": "Routes by Average Delivery Delay (hours)",
        "sql": """
            SELECT route_id, route_risk_level,
                   ROUND(AVG(delivery_delay_hours), 1) AS avg_delay_hours,
                   COUNT(*) AS late_shipments
            FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
            WHERE delivery_delay_hours > 0
            GROUP BY route_id, route_risk_level
            ORDER BY avg_delay_hours DESC LIMIT 15
        """,
        "chart_type": "horizontal_bar",
        "x": "AVG_DELAY_HOURS",
        "y": "ROUTE_ID",
        "color": "ROUTE_RISK_LEVEL",
    },
    "carrier_ontime": {
        "title": "Carriers by Late Delivery %",
        "sql": """
            SELECT carrier_name,
                   COUNT(*) AS total,
                   SUM(CASE WHEN is_on_time = FALSE THEN 1 ELSE 0 END) AS late,
                   ROUND(100.0 * SUM(CASE WHEN is_on_time = FALSE THEN 1 ELSE 0 END)
                       / NULLIF(SUM(CASE WHEN is_on_time IS NOT NULL THEN 1 ELSE 0 END), 0), 1) AS late_pct
            FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
            GROUP BY carrier_name
            ORDER BY late_pct DESC
        """,
        "chart_type": "horizontal_bar",
        "x": "LATE_PCT",
        "y": "CARRIER_NAME",
    },
    "delayed_by_route": {
        "title": "Delayed Shipments by Route",
        "sql": """
            SELECT route_id, route_risk_level, COUNT(*) AS delayed_count
            FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
            WHERE shipment_status = 'DELAYED'
            GROUP BY route_id, route_risk_level
            ORDER BY delayed_count DESC LIMIT 15
        """,
        "chart_type": "bar",
        "x": "ROUTE_ID",
        "y": "DELAYED_COUNT",
        "color": "ROUTE_RISK_LEVEL",
    },
    "route_delay_vs_cost": {
        "title": "Route Avg Delay vs Avg Shipping Cost",
        "sql": """
            SELECT route_id, route_risk_level,
                   ROUND(AVG(delivery_delay_hours), 1) AS avg_delay,
                   ROUND(AVG(shipping_cost), 2) AS avg_cost
            FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
            WHERE delivery_delay_hours IS NOT NULL
            GROUP BY route_id, route_risk_level
        """,
        "chart_type": "scatter",
        "x": "AVG_DELAY",
        "y": "AVG_COST",
        "color": "ROUTE_RISK_LEVEL",
        "tooltip": "ROUTE_ID",
    },

    # ── Inventory & Plant ────────────────────────────────────────
    "below_safety_by_plant": {
        "title": "Below-Safety-Stock Positions by Plant",
        "sql": """
            SELECT plant_name, COUNT(*) AS below_safety_count
            FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
            WHERE below_safety_stock = TRUE
            GROUP BY plant_name
            ORDER BY below_safety_count DESC
        """,
        "chart_type": "bar",
        "x": "PLANT_NAME",
        "y": "BELOW_SAFETY_COUNT",
    },
    "demand_coverage_by_plant": {
        "title": "Avg Days of Demand Coverage (90D) by Plant",
        "sql": """
            SELECT plant_name,
                   ROUND(AVG(days_of_demand_coverage_90d), 1) AS avg_coverage_days,
                   COUNT(*) AS positions
            FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
            WHERE days_of_demand_coverage_90d IS NOT NULL
            GROUP BY plant_name
            ORDER BY avg_coverage_days ASC
        """,
        "chart_type": "bar",
        "x": "PLANT_NAME",
        "y": "AVG_COVERAGE_DAYS",
    },
    "plant_backlog": {
        "title": "Plant Fulfillment Backlog ($)",
        "sql": """
            SELECT plant_name, COUNT(*) AS backlog_orders,
                   ROUND(SUM(outstanding_value), 0) AS outstanding_value
            FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT
            WHERE fulfillment_state IN ('UNFULFILLED', 'PARTIALLY_FULFILLED')
            GROUP BY plant_name
            ORDER BY outstanding_value DESC
        """,
        "chart_type": "horizontal_bar",
        "x": "OUTSTANDING_VALUE",
        "y": "PLANT_NAME",
    },
    "inventory_pressure_vs_backlog": {
        "title": "Plant: Inventory Pressure vs Fulfillment Backlog",
        "sql": """
            WITH inv AS (
                SELECT plant_name, COUNT(*) AS below_safety_count
                FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
                WHERE below_safety_stock = TRUE
                GROUP BY plant_name
            ),
            ful AS (
                SELECT plant_name, ROUND(SUM(outstanding_value)/1e6, 2) AS backlog_mm
                FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT
                WHERE fulfillment_state IN ('UNFULFILLED', 'PARTIALLY_FULFILLED')
                GROUP BY plant_name
            )
            SELECT inv.plant_name, inv.below_safety_count, ful.backlog_mm
            FROM inv JOIN ful ON inv.plant_name = ful.plant_name
        """,
        "chart_type": "scatter",
        "x": "BELOW_SAFETY_COUNT",
        "y": "BACKLOG_MM",
        "tooltip": "PLANT_NAME",
    },

    # ── Customer Impact ──────────────────────────────────────────
    "customer_outstanding_ranking": {
        "title": "Top 20 Customers by Outstanding Value ($)",
        "sql": """
            SELECT customer_name, customer_segment,
                   ROUND(outstanding_value, 0) AS outstanding_value,
                   ROUND(fulfillment_pct, 1) AS fulfillment_pct
            FROM SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT
            WHERE is_impacted = TRUE
            ORDER BY outstanding_value DESC LIMIT 20
        """,
        "chart_type": "horizontal_bar",
        "x": "OUTSTANDING_VALUE",
        "y": "CUSTOMER_NAME",
        "color": "CUSTOMER_SEGMENT",
    },
    "customer_fulfillment_distribution": {
        "title": "Customer Fulfillment % Distribution",
        "sql": """
            SELECT customer_name, customer_segment,
                   ROUND(fulfillment_pct, 1) AS fulfillment_pct,
                   total_late_order_count
            FROM SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT
            ORDER BY fulfillment_pct ASC LIMIT 30
        """,
        "chart_type": "horizontal_bar",
        "x": "FULFILLMENT_PCT",
        "y": "CUSTOMER_NAME",
        "color": "CUSTOMER_SEGMENT",
    },
    "customer_segment_summary": {
        "title": "Customer Segment: Avg Fulfillment & Outstanding Value",
        "sql": """
            SELECT customer_segment,
                   ROUND(AVG(fulfillment_pct), 1) AS avg_fill_pct,
                   ROUND(SUM(outstanding_value)/1e6, 2) AS outstanding_mm,
                   SUM(total_late_order_count) AS late_orders
            FROM SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT
            GROUP BY customer_segment ORDER BY avg_fill_pct
        """,
        "chart_type": "bar",
        "x": "CUSTOMER_SEGMENT",
        "y": "AVG_FILL_PCT",
    },

    # ── Overall / Orchestrator ───────────────────────────────────
    "cross_domain_risk_summary": {
        "title": "Cross-Domain Risk Summary",
        "sql": """
            SELECT 'Supplier Risk' AS domain, COUNT(*) AS entities,
                   SUM(CASE WHEN is_supplier_at_risk THEN 1 ELSE 0 END) AS at_risk
            FROM SUPPLY_CHAIN_DW.GOLD.MART_SUPPLIER_RISK
            UNION ALL
            SELECT 'Inventory', COUNT(*),
                   SUM(CASE WHEN below_safety_stock THEN 1 ELSE 0 END)
            FROM SUPPLY_CHAIN_DW.GOLD.MART_INVENTORY_RISK
            UNION ALL
            SELECT 'Order Fulfillment', COUNT(*),
                   SUM(CASE WHEN is_current_late THEN 1 ELSE 0 END)
            FROM SUPPLY_CHAIN_DW.GOLD.MART_ORDER_FULFILLMENT
            UNION ALL
            SELECT 'Logistics', COUNT(*),
                   SUM(CASE WHEN shipment_status = 'DELAYED' THEN 1 ELSE 0 END)
            FROM SUPPLY_CHAIN_DW.GOLD.MART_LOGISTICS_PERFORMANCE
            UNION ALL
            SELECT 'Customer Impact', COUNT(*),
                   SUM(CASE WHEN is_impacted THEN 1 ELSE 0 END)
            FROM SUPPLY_CHAIN_DW.GOLD.MART_CUSTOMER_IMPACT
        """,
        "chart_type": "bar",
        "x": "DOMAIN",
        "y": "AT_RISK",
    },
}


EXPERT_CHART_MAP = {
    "Procurement Expert": [
        "supplier_risk_score_ranking",
        "supplier_otd_vs_fill",
        "supplier_outstanding_exposure",
        "landed_cost_top",
    ],
    "Logistics Expert": [
        "route_delay_ranking",
        "carrier_ontime",
        "delayed_by_route",
        "route_delay_vs_cost",
    ],
    "Inventory & Plant Expert": [
        "below_safety_by_plant",
        "demand_coverage_by_plant",
        "plant_backlog",
        "inventory_pressure_vs_backlog",
    ],
    "Customer Impact Expert": [
        "customer_outstanding_ranking",
        "customer_fulfillment_distribution",
        "customer_segment_summary",
    ],
    "Overall Resilience Expert": [
        "cross_domain_risk_summary",
    ],
}


def detect_chart_intent(question: str, expert: str) -> str | None:
    """Return chart key if the question looks like a chart request for this expert."""
    q = question.lower()
    chart_triggers = ["chart", "visualize", "plot", "graph"]
    is_chart = any(t in q for t in chart_triggers)
    is_rank = "rank" in q and ("chart" in q or "generate" in q)
    is_compare = "compare" in q and ("chart" in q or "generate" in q)

    if not (is_chart or is_rank or is_compare):
        return None

    candidates = EXPERT_CHART_MAP.get(expert, [])
    keywords_map = {
        "supplier_risk_score_ranking": ["risk score", "ranking supplier", "rank supplier"],
        "supplier_otd_vs_fill": ["otd", "fill rate", "compare supplier"],
        "supplier_outstanding_exposure": ["exposure", "outstanding", "downstream"],
        "landed_cost_top": ["landed cost", "freight"],
        "route_delay_ranking": ["route", "delay"],
        "carrier_ontime": ["carrier", "on-time", "ontime"],
        "delayed_by_route": ["delayed shipment", "delayed by route"],
        "route_delay_vs_cost": ["delay", "cost", "compare route"],
        "below_safety_by_plant": ["safety stock", "below safety"],
        "demand_coverage_by_plant": ["demand coverage", "days of", "coverage"],
        "plant_backlog": ["backlog", "plant fulfillment", "plant outstanding"],
        "inventory_pressure_vs_backlog": ["pressure", "backlog", "combine", "inventory.*fulfillment"],
        "customer_outstanding_ranking": ["customer", "outstanding", "ranking customer"],
        "customer_fulfillment_distribution": ["fulfillment", "customer", "compare fulfillment"],
        "customer_segment_summary": ["segment"],
        "cross_domain_risk_summary": ["risk", "domain", "across", "summary", "top risk"],
    }

    for key in candidates:
        for kw in keywords_map.get(key, []):
            if kw in q:
                return key

    return candidates[0] if candidates else None
