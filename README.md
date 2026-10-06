# Resilient Supply Chain Control Tower

An agentic, Snowflake-native supply-chain resilience platform built for the **Snowflake CoCo CLI Hackathon**.

The project combines deterministic synthetic data, governed RAW → SILVER → GOLD pipelines, semantic views, Cortex Agents, Streamlit, CDC, and GitHub MCP actions to move from **risk detection** to **explainable operational action**.

---

## 1. Problem Statement

Supply-chain disruptions rarely stay inside one domain. A supplier deterioration can create an inventory shortage, delay fulfillment, disrupt logistics, and ultimately impact customers.

The challenge is not only to detect individual problems, but to answer questions such as:

- Which supplier deterioration is creating the highest downstream exposure?
- Which plants and parts are at risk of shortage?
- Which routes or carriers are amplifying delivery delays?
- Which customers are being impacted?
- What action should an operator take next?
- Can an AI agent create a governed operational case and raise an external work item after explicit approval?

This project addresses that problem with a **Resilient Supply Chain Control Tower** built entirely around Snowflake-native data and AI capabilities.

---

## 2. Solution Overview

The solution follows this flow:

```text
Synthetic ERP / Supplier / Logistics / Vehicle IoT data
                         |
                         v
                  RAW Snowflake Layer
                         |
                Streams + CDC Procedures
                         |
                         v
                 SILVER Dimensional Layer
                         |
                         v
                    GOLD Risk Marts
                         |
                         v
                  Semantic Views
                         |
             +-----------+-----------+
             |                       |
             v                       v
      Specialist Agents       Resilience Orchestrator
                                     |
                     +---------------+---------------+
                     |                               |
                     v                               v
              Governed Risk Case              GitHub MCP Issue
                     |
                     v
               Streamlit Control Tower
```

The important design principle is that the AI layer does **not** operate directly on uncontrolled raw tables. Business reasoning is grounded through curated marts and semantic views, while operational actions are explicitly governed.

---

## 3. Hackathon Feature Coverage

### Requested / Recommended Features

| Hackathon capability | Implementation | Repository location |
|---|---|---|
| Synthetic data generation | Deterministic multi-domain supply-chain generator with scenario propagation | `generator/`, `DATA_GENERATION_CONTRACT.md` |
| Incremental / pipeline creation | RAW, SILVER, GOLD layers plus Streams, CDC procedures and Tasks | `migrations/`, `silver/`, `gold/` |
| Streams | RAW CDC streams for incremental source changes | `migrations/V3.8.0__create_raw_cdc_streams.sql` |
| Tasks | Triggered CDC tasks created and intentionally kept suspended for controlled demo execution | `migrations/V3.11.0__create_cdc_tasks.sql` |
| Dynamic Table | Logistics Gold mart conversion is implemented as an optional migration | `migrations/V3.16.0__convert_mart_logistics_performance_to_dynamic_table.sql` |
| Semantic model / ontology | Six Snowflake Semantic Views over governed Gold marts | `semantic/` |
| AI / Cortex Agents | Five domain specialists plus a cross-domain resilience orchestrator | `agents/` |
| Streamlit experience | Conversational supply-chain Control Tower, risk-case viewer and expert selection | `streamlit_app/` |
| MCP connector | GitHub MCP connected to the resilience orchestrator for governed issue creation | `agents/resilience_orchestrator_updated.sql` + Snowflake external MCP configuration |
| Validation | Grain, referential integrity, derived metric, scenario and Gold mart validation suites | `validations/` |

---

## 4. Why We Added More Than the Minimum

The hackathon requirements can be satisfied with data generation, a pipeline, semantic intelligence and an application. We added several capabilities because a resilient supply-chain system should demonstrate **operational credibility**, not only analytical output.

### 4.1 Multi-Agent Architecture

**Why:** Supply-chain decisions span several business domains. A single generic agent tends to mix grains, invent relationships, or overreach across unrelated metrics.

**What we added:**

- Supplier Risk Agent
- Inventory Risk Agent
- Logistics Risk Agent
- Plant Fulfillment Agent
- Customer Impact Agent
- Resilience Orchestrator

**Where:** `agents/`

The orchestrator delegates domain-specific analysis while keeping cross-domain reasoning explicit.

### 4.2 Governed Risk-Case Actions

**Why:** An agent should not directly mutate operational business tables. High-impact actions need a controlled boundary.

**What we added:**

- `CONTROL.RISK_CASE`
- `CONTROL.SP_CREATE_RISK_CASE`
- severity validation
- structured success / failure response
- explicit human-request requirement before action

**Where:**

- `migrations/V3.17.0__create_risk_case_table.sql`
- `migrations/V3.18.0__create_risk_case_procedure.sql`
- `agents/resilience_orchestrator_updated.sql`

This creates a clear separation between **AI reasoning** and **governed operational action**.

### 4.3 GitHub MCP Integration

**Why:** Detecting a risk is useful; turning it into tracked work is more valuable.

The orchestrator can, after explicit user approval:

1. analyze a supply-chain disruption;
2. create an internal Snowflake risk case;
3. call GitHub through MCP;
4. create an Issue in `parasara93/CoCoHackathon`;
5. include evidence, severity, business impact and the Snowflake risk-case ID.

This gives the project a complete:

```text
Detect -> Explain -> Approve -> Act -> Track
```

workflow.

**Where:**

- orchestration rules: `agents/resilience_orchestrator_updated.sql`
- GitHub MCP server / OAuth objects: configured in Snowflake
- external repository: `parasara93/CoCoHackathon`

A complete end-to-end test successfully created a governed risk case and GitHub Issue through the orchestrator.

### 4.4 CDC Instead of Full Reload Only

**Why:** Supply-chain data changes continuously. A resilience system that only works after complete rebuilds is not operationally realistic.

**What we added:**

- nine RAW streams;
- eight CDC stored procedures;
- eight triggered tasks;
- CDC execution logs;
- incremental batch loader;
- batch validator.

**Where:**

```text
migrations/V3.8.0__create_raw_cdc_streams.sql
migrations/V3.9.0__create_cdc_control_log.sql
migrations/V3.10.0__create_cdc_procedures.sql
migrations/V3.11.0__create_cdc_tasks.sql
migrations/V3.12.0__validate_cdc_objects.sql
migrations/V3.14.0__create_incremental_raw_loader.sql
migrations/V3.15.0__create_cdc_batch_validator.sql
```

The demo validated a stream-driven incremental path by propagating new shipment events from RAW to SILVER while keeping scheduled tasks suspended for controlled execution.

### 4.5 Deterministic Scenario Grounding

**Why:** Random synthetic data can make an AI demo look convincing without proving that the platform actually detects intended business failures.

The generator contains deterministic disruption scenarios so expected behavior can be validated.

Examples include:

- supplier deterioration;
- inventory shortage;
- plant bottleneck;
- logistics disruption;
- downstream customer impact.

**Where:**

- `generator/`
- `DATA_GENERATION_CONTRACT.md`
- `validations/silver/scenario_checks.sql`
- related Gold validation scripts under `validations/gold/`

### 4.6 Schema Change Management

**Why:** AI-generated SQL should still follow normal engineering controls.

**What we added:**

- versioned SQL migrations;
- repeatable deployment structure;
- schema-change configuration;
- persistent engineering instructions.

**Where:**

- `migrations/`
- `schemachange-config.yml`
- `AGENTS.md`
- `docs/`

This keeps AI-assisted development auditable and prevents uncontrolled direct changes to production-style objects.

---

## 5. Data Architecture

### RAW

Operationally-shaped source tables covering customers, plants, parts, suppliers, carriers, routes, orders, order lines, inventory, shipments, shipment lines, shipment events, supplier-part relationships, supplier performance, and vehicle telemetry.

**DDL:** `migrations/V1.0.0__create_raw_schema_and_tables.sql`

### SILVER

The Silver layer converts RAW data into governed dimensional structures.

It contains:

- 7 dimensions
- 7 facts
- 1 supplier-part bridge

Baseline transformations are under:

```text
silver/baseline/
```

Important patterns include deterministic deduplication, explicit grain declarations, derived logistics / inventory fields, controlled fact-to-dimension relationships, and history preservation for events and telemetry.

### GOLD

Six analytical marts support the AI and application layers:

| Mart | Grain | Purpose |
|---|---|---|
| `MART_SUPPLIER_RISK` | Supplier | Supplier deterioration and downstream exposure |
| `MART_INVENTORY_RISK` | Plant + Part | Shortage, safety stock and demand coverage |
| `MART_LOGISTICS_PERFORMANCE` | Shipment | Delay, route, carrier and disruption analysis |
| `MART_ORDER_FULFILLMENT` | Order | Fulfillment, backlog and lateness |
| `MART_CUSTOMER_IMPACT` | Customer | Customer-level downstream impact |
| `MART_LANDED_COST` | Supplier + Part | Estimated landed unit cost |

**DDL:** `migrations/V3.1.0` through `V3.7.0`

**Population logic:** `gold/`

---

## 6. Semantic Layer

Six Semantic Views expose governed business concepts to Cortex Analyst / Cortex Agents:

```text
semantic/
├── sv_supplier_risk.sql
├── sv_inventory_risk.sql
├── sv_logistics_performance.sql
├── sv_order_fulfillment.sql
├── sv_customer_impact.sql
└── sv_landed_cost.sql
```

Each semantic view was validated by successful `DESCRIBE SEMANTIC VIEW`, generated Cortex Analyst SQL, successful execution against current Gold data, and representative business questions.

The semantic layer acts as the context boundary between physical marts and AI reasoning.

---

## 7. Agent Architecture

```text
RESILIENCE_ORCHESTRATOR
|
+-- SUPPLIER_RISK_AGENT
|    +-- Supplier Semantic View
|    +-- Inventory Semantic View
|
+-- INVENTORY_RISK_AGENT
|    +-- Inventory Semantic View
|    +-- Supplier Semantic View
|
+-- LOGISTICS_RISK_AGENT
|    +-- Logistics Semantic View
|    +-- Order Fulfillment Semantic View
|
+-- PLANT_FULFILLMENT_AGENT
|    +-- Order Fulfillment Semantic View
|    +-- Inventory Semantic View
|
+-- CUSTOMER_IMPACT_AGENT
     +-- Customer Impact Semantic View
     +-- Order Fulfillment Semantic View
```

The orchestrator additionally owns governed action tools:

```text
create_risk_case
GitHub MCP
```

**Definitions:** `agents/`

---

## 8. Streamlit Control Tower

The application provides a judge / business-user-facing interface.

### Experts

- Procurement Expert
- Inventory & Plant Expert
- Plant Fulfillment Expert
- Logistics Expert
- Customer Impact Expert
- Overall Resilience Expert

### Capabilities

- suggested business questions;
- free-form conversational analysis;
- specialist or orchestrated reasoning;
- optional charts;
- governed risk-case viewer;
- operational risk-case creation;
- GitHub issue creation through the orchestrator and MCP.

**Where:** `streamlit_app/`

The UI does **not** directly call GitHub. External actions stay behind the governed orchestrator.

---

## 9. Validation Strategy

Validation is treated as part of the architecture rather than an afterthought.

### Silver validation

`validations/silver/`

Checks include grain uniqueness, dimension keys, referential integrity, derived columns, and scenario preservation.

The current deployment passed all grain, dimension-key, derived-column and scenario checks. A small number of Silver RI exceptions were traced to known source-data gaps rather than transformation fan-out.

### Gold validation

`validations/gold/`

The deployed Gold layer completed **87 / 87 validation checks successfully** across all six marts.

Checks included declared grain, null safety, reconciliation to Silver, formula correctness, fan-out prevention, business scenario signals, and metric bounds.

---

## 10. CDC Demonstration

The CDC design exists independently of the historical baseline load.

A controlled demo validated:

```text
RAW incremental event
-> RAW stream
-> CDC stored procedure
-> SILVER fact
-> CDC execution log
```

Three new shipment events were successfully captured and propagated into `SILVER.FACT_SHIPMENT_EVENT`.

All CDC tasks are deliberately left **SUSPENDED** in the demo environment so the pipeline can be demonstrated deterministically without background executions interfering with the presentation.

---

## 11. Scenario Coverage

The synthetic dataset contains five connected resilience scenarios.

| Scenario | Business signal |
|---|---|
| Supplier deterioration | Falling delivery / quality performance and increasing supplier risk |
| Inventory shortage | Safety-stock and reorder pressure for critical parts |
| Plant bottleneck | Growing backlog and fulfillment degradation |
| Logistics disruption | Route deviation, delays and elevated transport risk |
| Customer impact | Late / unfulfilled demand propagating to customers |

The scenarios are intentionally propagated across source domains so the Control Tower can reason about downstream impact instead of isolated anomalies.

---

## 12. Repository Structure

```text
.
├── agents/                     # Specialist Cortex Agents + resilience orchestrator
├── docs/                       # Engineering / change-management documentation
├── generator/                  # Deterministic synthetic data generator
├── gold/                       # Gold mart population SQL
├── migrations/                 # Versioned Snowflake DDL / CDC / governance migrations
├── migrations_original/        # Archived historical migrations - not for deployment
├── prompts/                    # Important CoCo development prompts
├── semantic/                   # Snowflake Semantic Views
├── silver/                     # Silver baseline transformation SQL
├── streamlit_app/              # Resilient Supply Chain Control Tower UI
├── validation/                 # Supporting validation assets
├── validations/                # Executable Silver / Gold validation SQL
├── AGENTS.md                   # Persistent AI engineering instructions
├── DATA_GENERATION_CONTRACT.md # Dataset contract and scenario specification
└── schemachange-config.yml     # Schema-change configuration
```

> **Deployment note:** use `migrations/`. `migrations_original/` is retained only as historical reference.

---

## 13. Recommended Deployment Order

```text
1. RAW schema and tables
2. Historical baseline load
3. SILVER schema + baseline transformations
4. SILVER validations
5. GOLD schema + marts
6. GOLD validations
7. Semantic Views
8. Specialist Agents
9. Resilience Orchestrator
10. CONTROL / Risk Case objects
11. GitHub MCP integration
12. Streamlit
13. Streams / CDC procedures / Tasks
14. Optional Dynamic Table migration
```

For controlled demos, CDC Tasks can remain suspended and the procedures can be invoked manually.

---

## 14. Example End-to-End Agentic Workflow

Example request:

```text
Analyze route RTE-000036.
If the evidence supports a material disruption,
create a governed internal risk case and raise a GitHub issue.
```

The platform can execute:

```text
User
  |
  v
Streamlit
  |
  v
RESILIENCE_ORCHESTRATOR
  |
  +--> Logistics specialist / semantic analysis
  |
  +--> Evidence + severity + recommendation
  |
  +--> CONTROL.SP_CREATE_RISK_CASE
  |        |
  |        +--> CONTROL.RISK_CASE
  |
  +--> GitHub MCP
           |
           +--> GitHub Issue
```

This workflow was validated end-to-end with both the Snowflake risk case and GitHub Issue successfully created.

---

## 15. Design Principles

The project intentionally follows several rules:

- declare business grain before joins;
- pre-aggregate before joining across different grains;
- validate every material schema / transformation change;
- prefer deterministic scenario generation;
- keep AI reasoning grounded in curated semantic objects;
- never allow an AI agent to write directly to core business tables;
- require explicit user intent for external actions;
- persist operational actions through governed Snowflake procedures;
- use MCP for external-system actions rather than embedding direct API credentials in the UI.

---

## 16. Future Scope

The current prototype establishes the core resilient-control-tower architecture. Natural next steps include:

- production-grade event ingestion / Snowpipe Streaming;
- automatic Gold refresh after CDC processing;
- broader Dynamic Table adoption;
- persisted validation history and observability dashboards;
- closed-loop GitHub status synchronization;
- supplier / carrier notification workflows;
- approval workflows for high-severity agent actions;
- richer scenario simulation and probabilistic disruption forecasting;
- cost / SLA-aware agent orchestration;
- production authentication and role-based application access.

---

## 17. What This Prototype Demonstrates

The project goes beyond a conversational dashboard.

It demonstrates that CoCo-assisted engineering can build and validate a governed Snowflake data product that combines:

**data engineering + semantic modeling + agentic reasoning + operational governance + external actions.**

The resulting platform can:

```text
observe supply-chain data
-> detect risk
-> explain evidence
-> reason across domains
-> recommend action
-> create a governed case
-> create an external operational issue
```

while keeping the underlying data model, validations, and actions auditable.

---

## Built With

- Snowflake
- Snowflake CoCo CLI / CoCo Desktop
- Snowflake Streams & Tasks
- Snowflake Dynamic Tables
- Snowflake Cortex Analyst
- Snowflake Cortex Agents
- Snowflake Semantic Views
- Streamlit in Snowflake
- External MCP
- GitHub
- schemachange
- Python
- SQL
