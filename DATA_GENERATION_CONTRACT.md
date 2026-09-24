# Supply Chain Synthetic Data Generation Contract v1.0

## 1. Purpose

Generate a realistic, deterministic synthetic supply-chain dataset that emulates data scattered across four operational source domains:

* ERP
* Supplier systems
* Logistics systems
* Vehicle IoT systems

The generated data must support downstream ingestion into Snowflake, incremental processing, cross-domain analytics, AI/agent investigation, semantic modeling, and Streamlit visualization.

The generated operational data must look natural and must not expose artificial scenario labels inside business tables.

---

# 2. Global Rules

## Time Period

Generate 12 months of synthetic data.

Use the synthetic timeline ending in September 2026.

## Deterministic Generation

Use a fixed random seed.

Running the generator with the same configuration must produce the same records and scenario behavior.

## File Format

All source files must be CSV.

## Source Domains

Use the following logical source structure:

```text
supply-chain/
    erp/
        customers/
        plants/
        orders/
        order_lines/
        inventory/

    supplier/
        suppliers/
        parts/
        supplier_parts/
        supplier_performance/

    logistics/
        carriers/
        routes/
        shipments/
        shipment_lines/
        shipment_events/

    iot/
        vehicle_telemetry/

    validation/
        scenario_ground_truth/
```

Operational tables must not contain fields such as:

```text
scenario_1_supplier_deterioration
scenario_type
scenario_name
is_synthetic_scenario
```

Scenario information must exist only in the validation/ground-truth dataset.

---

# 3. Core Entity Volumes

Target approximate entity volumes:

| Entity            |                                                           Target Volume |
| ----------------- | ----------------------------------------------------------------------: |
| Suppliers         |                                                                      75 |
| Parts             |                                                                     750 |
| Plants            |                                                                      15 |
| Customers         |                                                                   1,500 |
| Orders            |                                                                ~100,000 |
| Order Lines       |                                                        ~200,000–300,000 |
| Shipments         |                                                                ~120,000 |
| Inventory records | ~11,250 base plant-part combinations or an appropriate realistic subset |
| Carriers          |                                                                   15–25 |
| Routes            |                                                                 100–250 |
| Vehicles          |                          Enough to realistically serve active shipments |

Exact transactional volumes may vary slightly if needed to maintain referential and business consistency.

---

# 4. ERP Domain

## 4.1 customers

Primary key:

```text
customer_id
```

Columns:

```text
customer_id VARCHAR
customer_name VARCHAR
customer_segment VARCHAR
city VARCHAR
state VARCHAR
country VARCHAR
latitude NUMBER
longitude NUMBER
created_at TIMESTAMP
```

Rules:

* `customer_id` must be unique.
* Geography must be internally consistent.
* Latitude and longitude should approximately correspond to customer geography.
* Customers may have many orders.

---

## 4.2 plants

Primary key:

```text
plant_id
```

Columns:

```text
plant_id VARCHAR
plant_name VARCHAR
city VARCHAR
state VARCHAR
country VARCHAR
latitude NUMBER
longitude NUMBER
capacity_units NUMBER
created_at TIMESTAMP
```

Rules:

* Plants represent both manufacturing and operational fulfillment locations.
* Every plant must have a realistic positive capacity.
* Plants may serve multiple customers.

---

## 4.3 orders

Primary key:

```text
order_id
```

Foreign keys:

```text
customer_id -> customers.customer_id
plant_id -> plants.plant_id
```

Columns:

```text
order_id VARCHAR
customer_id VARCHAR
plant_id VARCHAR
order_date TIMESTAMP
requested_delivery_date DATE
order_status VARCHAR
order_total NUMBER
last_updated_at TIMESTAMP
```

Suggested statuses:

```text
CREATED
CONFIRMED
PROCESSING
PARTIALLY_SHIPPED
SHIPPED
DELIVERED
CANCELLED
```

Rules:

* Every order must reference a valid customer.
* Every order must reference a valid plant.
* One order may contain parts supplied by multiple suppliers.
* Supplier information must not be stored directly at order level.
* `requested_delivery_date >= order_date`.

---

## 4.4 order_lines

Primary key:

```text
order_line_id
```

Foreign keys:

```text
order_id -> orders.order_id
part_id -> parts.part_id
```

Columns:

```text
order_line_id VARCHAR
order_id VARCHAR
part_id VARCHAR
ordered_qty NUMBER
unit_price NUMBER
line_amount NUMBER
line_status VARCHAR
created_at TIMESTAMP
last_updated_at TIMESTAMP
```

Rules:

```text
line_amount = ordered_qty * unit_price
```

* One order can contain multiple order lines.
* Different lines in the same order may ultimately be sourced from different suppliers.
* Every referenced part must exist.

---

## 4.5 inventory

Logical key:

```text
plant_id + part_id
```

Foreign keys:

```text
plant_id -> plants.plant_id
part_id -> parts.part_id
```

Columns:

```text
plant_id VARCHAR
part_id VARCHAR
on_hand_qty NUMBER
reserved_qty NUMBER
available_qty NUMBER
safety_stock NUMBER
reorder_point NUMBER
inventory_status VARCHAR
last_updated_at TIMESTAMP
```

Required calculation:

```text
available_qty = on_hand_qty - reserved_qty
```

Rules:

* Quantities cannot be negative unless intentionally modeling backorders, which should be avoided for v1.
* Inventory updates must change over time as orders, receipts, and scenario events occur.
* Low inventory must be capable of affecting order fulfillment.

---

# 5. Supplier Domain

## 5.1 suppliers

Primary key:

```text
supplier_id
```

Columns:

```text
supplier_id VARCHAR
supplier_name VARCHAR
city VARCHAR
state VARCHAR
country VARCHAR
supplier_tier VARCHAR
supplier_status VARCHAR
created_at TIMESTAMP
```

Possible statuses:

```text
ACTIVE
AT_RISK
SUSPENDED
```

---

## 5.2 parts

Primary key:

```text
part_id
```

Columns:

```text
part_id VARCHAR
part_name VARCHAR
part_category VARCHAR
unit_of_measure VARCHAR
standard_cost NUMBER
criticality VARCHAR
created_at TIMESTAMP
```

Suggested criticality:

```text
LOW
MEDIUM
HIGH
CRITICAL
```

---

## 5.3 supplier_parts

Logical key:

```text
supplier_id + part_id
```

Foreign keys:

```text
supplier_id -> suppliers.supplier_id
part_id -> parts.part_id
```

Columns:

```text
supplier_id VARCHAR
part_id VARCHAR
supplier_unit_cost NUMBER
base_lead_time_days NUMBER
minimum_order_qty NUMBER
preferred_supplier_flag BOOLEAN
active_flag BOOLEAN
last_updated_at TIMESTAMP
```

Rules:

* A part may have multiple approved suppliers.
* A supplier may supply multiple parts.
* At least one active supplier must exist for every actively used part.
* Preferably, many important parts should have 2–3 suppliers.
* Only one supplier should normally be marked preferred for a given part.

---

## 5.4 supplier_performance

Primary key can be generated as:

```text
supplier_performance_id
```

Foreign key:

```text
supplier_id -> suppliers.supplier_id
```

Columns:

```text
supplier_performance_id VARCHAR
supplier_id VARCHAR
measurement_date DATE
avg_lead_time_days NUMBER
on_time_delivery_pct NUMBER
quality_score NUMBER
fill_rate_pct NUMBER
risk_score NUMBER
last_updated_at TIMESTAMP
```

Rules:

* Performance should vary naturally over time.
* Scenario-affected suppliers must deteriorate gradually rather than change randomly in one record.
* Performance metrics must influence downstream supplier reliability.

---

# 6. Logistics Domain

## 6.1 carriers

Primary key:

```text
carrier_id
```

Columns:

```text
carrier_id VARCHAR
carrier_name VARCHAR
carrier_type VARCHAR
service_level VARCHAR
base_cost_per_km NUMBER
active_flag BOOLEAN
created_at TIMESTAMP
```

Rules:

* One carrier can serve multiple plants.
* One carrier can operate multiple routes.
* One carrier can carry many shipments.

---

## 6.2 routes

Primary key:

```text
route_id
```

Columns:

```text
route_id VARCHAR
origin_type VARCHAR
origin_id VARCHAR
destination_type VARCHAR
destination_id VARCHAR
distance_km NUMBER
expected_transit_hours NUMBER
route_risk_level VARCHAR
created_at TIMESTAMP
```

Allowed origin/destination types:

```text
SUPPLIER
PLANT
CUSTOMER
```

Rules:

* Routes must represent both inbound and outbound movements.
* Distances and transit times must be reasonable.
* Routes should be reused across shipments.

---

## 6.3 shipments

Primary key:

```text
shipment_id
```

Foreign keys:

```text
carrier_id -> carriers.carrier_id
route_id -> routes.route_id
```

Columns:

```text
shipment_id VARCHAR
shipment_type VARCHAR
carrier_id VARCHAR
route_id VARCHAR
shipment_status VARCHAR
planned_departure_at TIMESTAMP
actual_departure_at TIMESTAMP
planned_delivery_at TIMESTAMP
actual_delivery_at TIMESTAMP
shipping_cost NUMBER
last_updated_at TIMESTAMP
```

Allowed shipment types:

```text
INBOUND
OUTBOUND
```

Allowed statuses:

```text
PLANNED
PICKED_UP
IN_TRANSIT
DELAYED
DELIVERED
CANCELLED
```

Rules:

For inbound shipments:

```text
supplier -> plant
```

For outbound shipments:

```text
plant -> customer
```

Shipment timestamps must follow logical chronological order.

Example:

```text
planned_departure_at <= planned_delivery_at
actual_departure_at <= actual_delivery_at
```

when both actual values exist.

---

## 6.4 shipment_lines

Primary key:

```text
shipment_line_id
```

Foreign keys:

```text
shipment_id -> shipments.shipment_id
order_line_id -> order_lines.order_line_id
```

Columns:

```text
shipment_line_id VARCHAR
shipment_id VARCHAR
order_line_id VARCHAR
part_id VARCHAR
shipped_qty NUMBER
created_at TIMESTAMP
```

Rules:

* One shipment may contain multiple order lines.
* One order may be fulfilled across multiple shipments.
* `part_id` must agree with the referenced `order_line_id`.
* Total shipped quantity for an order line should not exceed ordered quantity, except where explicitly modeling correction events.

---

## 6.5 shipment_events

Primary key:

```text
shipment_event_id
```

Foreign key:

```text
shipment_id -> shipments.shipment_id
```

Columns:

```text
shipment_event_id VARCHAR
shipment_id VARCHAR
event_timestamp TIMESTAMP
event_type VARCHAR
location_latitude NUMBER
location_longitude NUMBER
event_description VARCHAR
```

Possible event types:

```text
CREATED
PICKED_UP
DEPARTED
ARRIVED_HUB
DELAY_REPORTED
ROUTE_DEVIATION
ARRIVED_DESTINATION
DELIVERED
```

Rules:

* Event timestamps must be chronological within each shipment.
* Shipment events must agree with shipment status progression.

---

# 7. IoT Domain

## 7.1 vehicle_telemetry

Primary key:

```text
telemetry_id
```

Columns:

```text
telemetry_id VARCHAR
vehicle_id VARCHAR
shipment_id VARCHAR
event_timestamp TIMESTAMP
latitude NUMBER
longitude NUMBER
speed_kmph NUMBER
vehicle_status VARCHAR
distance_travelled_km NUMBER
```

Foreign key:

```text
shipment_id -> shipments.shipment_id
```

Rules:

* One shipment has one active vehicle assignment in the v1 model.
* Vehicle IoT data is generated primarily for active shipments.
* No temperature telemetry is required.
* Location should progress plausibly along the route.
* Speed cannot be negative.
* Delivered shipments should stop producing active transit telemetry.

Possible vehicle statuses:

```text
MOVING
IDLE
STOPPED
DELAYED
OFF_ROUTE
ARRIVED
```

---

# 8. Incremental Data Generation

## ERP, Supplier, Logistics

Generate five incremental batches per day.

The conceptual daily schedule may be:

```text
06:30
09:30
12:30
15:30
18:30
```

Exact timestamps can be configurable, but each batch must be chronologically ordered.

Each incremental batch may contain:

* inserts
* updates

Examples:

```text
new order inserted
existing order status updated
inventory quantity updated
supplier performance updated
shipment status updated
shipment event inserted
```

Records must retain stable business keys across updates.

Do not generate a new `shipment_id` merely because a shipment status changes.

---

# 9. IoT Frequency

IoT telemetry should approximate real operational behavior.

Use:

```text
hourly telemetry for active shipments
```

Do not generate hourly telemetry for every vehicle for the full 12 months.

Recommended strategy:

* older historical IoT: lower-density representative records
* recent/active shipments: hourly telemetry
* scenario-affected shipments: sufficient hourly telemetry to demonstrate disruption clearly

This keeps the data realistic while controlling dataset size.

---

# 10. Historical and Incremental File Strategy

Use two conceptual phases.

## Phase A — Historical Backfill

Generate historical data covering most of the 12-month period.

Historical data may use larger periodic files.

Example:

```text
orders_2025_10.csv
orders_2025_11.csv
...
```

## Phase B — Incremental Simulation

For the recent period, produce five source batches per day.

Example:

```text
orders_20260920_0630.csv
orders_20260920_0930.csv
orders_20260920_1230.csv
orders_20260920_1530.csv
orders_20260920_1830.csv
```

Equivalent batch patterns should exist for changing Supplier and Logistics datasets.

IoT should use hourly files or logically equivalent hourly partitions.

---

# 11. Scenario Design

Generate five controlled cross-domain disruption scenarios.

The scenarios must create observable business signals across multiple source systems.

## Scenario 1 — Supplier Deterioration

Cause:

A previously reliable supplier gradually deteriorates.

Expected effects:

```text
supplier performance declines
lead time increases
on-time delivery percentage falls
inbound shipments become delayed
plant inventory for affected parts decreases
order fulfillment risk increases
outbound customer shipments may become delayed
```

---

## Scenario 2 — Inventory Shortage

Cause:

Demand increases or replenishment is insufficient for selected critical parts.

Expected effects:

```text
available inventory declines
inventory approaches/breaches safety stock
order lines remain unfulfilled or partially fulfilled
outbound shipments are delayed
customer delivery risk increases
```

---

## Scenario 3 — Plant Bottleneck

Cause:

A plant experiences temporary capacity pressure.

Expected effects:

```text
order processing time increases
inventory reservation increases
shipment departures are delayed
backlog grows
requested delivery dates become harder to meet
```

---

## Scenario 4 — Logistics / Landed-Cost Disruption

Cause:

A selected route or carrier experiences operational disruption.

Expected effects:

```text
transit time increases
route deviations may appear
vehicle telemetry shows delay/off-route behavior
shipment delivery delays increase
shipping cost increases
landed cost impact becomes visible
```

---

## Scenario 5 — Customer Impact

Cause:

Downstream culmination of upstream disruption.

Expected effects:

```text
affected customer orders experience delays
partial shipments may occur
actual delivery dates exceed requested dates
customer-level service metrics deteriorate
```

This scenario should largely be produced by effects from other operational disruptions rather than independent random labels.

---

# 12. Scenario Ground Truth

Create a separate validation file:

```text
scenario_ground_truth.csv
```

Suggested columns:

```text
scenario_id
scenario_type
scenario_start_timestamp
scenario_end_timestamp
primary_entity_type
primary_entity_id
affected_supplier_ids
affected_part_ids
affected_plant_ids
affected_route_ids
affected_shipment_ids
affected_order_ids
expected_business_effect
```

This file is only for:

* validating the synthetic generator
* confirming the AI agent discovers the intended relationships
* evaluating hackathon demonstrations

Do not load scenario labels into core operational source tables unless needed in a private validation schema.

---

# 13. Scenario Generation Principles

Scenario behavior must be deterministic.

The generator must not simply mark records as disrupted.

Instead, it must modify actual operational values.

For example, supplier deterioration must change values such as:

```text
avg_lead_time_days
on_time_delivery_pct
shipment planned vs actual dates
inventory levels
order fulfillment timing
```

The AI agent must be able to infer the disruption from the business data without reading the ground-truth file.

---

# 14. Referential Integrity Requirements

The following must always be true:

```text
orders.customer_id exists in customers.customer_id

orders.plant_id exists in plants.plant_id

order_lines.order_id exists in orders.order_id

order_lines.part_id exists in parts.part_id

supplier_parts.supplier_id exists in suppliers.supplier_id

supplier_parts.part_id exists in parts.part_id

inventory.plant_id exists in plants.plant_id

inventory.part_id exists in parts.part_id

shipments.carrier_id exists in carriers.carrier_id

shipments.route_id exists in routes.route_id

shipment_lines.shipment_id exists in shipments.shipment_id

shipment_lines.order_line_id exists in order_lines.order_line_id

vehicle_telemetry.shipment_id exists in shipments.shipment_id
```

No orphan records are permitted.

---

# 15. Business Validation Rules

The generator must validate at minimum:

### Keys

* primary keys are unique
* no unexpected duplicate rows
* all required foreign keys resolve

### Quantities

* ordered quantities > 0
* shipped quantities > 0
* costs >= 0
* inventory quantities remain logically valid

### Inventory

```text
available_qty = on_hand_qty - reserved_qty
```

### Order Lines

```text
line_amount = ordered_qty * unit_price
```

### Timestamps

* timestamps occur within the configured 12-month timeline
* event sequences are chronological
* delivery cannot occur before shipment departure
* shipment events cannot occur before shipment creation

### Shipment Status

Status transitions must be realistic.

For example:

```text
PLANNED
→ PICKED_UP
→ IN_TRANSIT
→ DELIVERED
```

or:

```text
PLANNED
→ PICKED_UP
→ IN_TRANSIT
→ DELAYED
→ IN_TRANSIT
→ DELIVERED
```

### IoT

* coordinates should show reasonable movement
* telemetry timestamps must increase
* speed >= 0
* off-route scenarios must show measurable route deviation
* delivered shipments must cease active movement

---

# 16. Incremental Batch Validation

Each generated batch must be validated independently.

Validate:

* chronological batch timestamp
* stable primary/business keys
* updates reference records that previously existed
* new records do not collide with existing keys
* update records actually change one or more business attributes
* no accidental duplicate full snapshots unless explicitly intended
* scenario events occur only within configured scenario windows

---

# 17. Required Generator Outputs

The generator must produce:

1. Synthetic CSV source files
2. Incremental batch files
3. Scenario ground-truth file
4. Validation report
5. Row-count summary by table
6. Referential-integrity summary
7. Scenario-effect validation summary
8. Generator configuration containing the deterministic seed

---

# 18. Generation Safety Process

Do not generate the full dataset immediately.

Follow this sequence:

### Step 1

Generate a very small sample of every entity.

### Step 2

Run all validation rules.

### Step 3

Inspect relationships and scenario propagation.

### Step 4

Correct generator logic if required.

### Step 5

Generate a medium-sized test dataset.

### Step 6

Validate incremental batches and update behavior.

### Step 7

Only after successful validation, generate the full 12-month dataset.

### Step 8

Run full validation again.

### Step 9

Only validated files should be uploaded to S3 or Snowflake.

---

# 19. What CoCo Must Not Do

CoCo must not:

* invent new tables without explicit approval
* rename required primary or foreign keys
* randomly change established relationships
* expose scenario labels in production-style operational data
* create orphan foreign keys
* generate full data before sample validation
* upload files before validation
* generate unrealistic timestamps or shipment transitions
* create independent random disruptions that break causal scenario relationships
* create temperature IoT data
* generate excessive IoT history that does not contribute to the use case

---

# 20. Acceptance Criteria

The dataset is accepted only if:

* all required tables are generated
* all primary keys are unique
* all foreign keys resolve
* agreed entity volumes are approximately achieved
* ERP/Supplier/Logistics batches support 5 updates per day
* active IoT shipments support hourly telemetry
* insert and update behavior is present
* all five disruption scenarios are represented
* scenario effects propagate across multiple domains
* operational tables contain no scenario labels
* scenario ground truth matches generated effects
* validation produces no critical integrity failures
* output is deterministic under the configured seed
