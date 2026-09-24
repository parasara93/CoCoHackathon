# Scenario Validation Summary

## Purpose

The synthetic dataset contains five deterministic disruption scenarios.

Scenario labels are not added to operational business tables.

The AI/analytics layer is expected to discover the disruption using actual operational signals across ERP, Supplier, Logistics, and IoT data.

Scenario definitions are stored separately in:

scenario_ground_truth

---

# Scenario 1 — Supplier Deterioration

## Objective

Model the gradual deterioration of a previously reliable supplier.

## Propagation

Supplier performance deterioration
→ longer lead times
→ lower on-time delivery
→ lower fill rate
→ higher supplier risk
→ inbound shipment delays
→ reduced plant inventory
→ downstream order fulfillment risk

## Final Full Run

Target supplier:

SUP-000062

Observed impact:

- 1,882 related shipments
- 3,104 affected orders
- 66 affected inventory records

## Result

FULLY OBSERVED

---

# Scenario 2 — Inventory Shortage

## Objective

Simulate shortage of critical parts.

## Propagation

Critical-part shortage
→ available inventory decreases
→ safety stock breached
→ order lines cannot be fulfilled normally
→ outbound shipments delayed
→ customer orders become at risk

## Final Full Run

Target:

4 critical parts

Observed impact:

- 16 affected inventory records
- 211 affected orders
- 8 affected shipments

## Result

FULLY OBSERVED

---

# Scenario 3 — Plant Bottleneck

## Objective

Simulate operational capacity pressure at a plant.

## Propagation

Plant pressure
→ inventory reservations increase
→ available inventory decreases
→ processing backlog increases
→ order processing is delayed
→ outbound shipments delayed
→ delivery risk increases

Advanced order statuses are not artificially regressed.

Processing delay is represented through realistic status behavior and timestamps.

## Final Full Run

Target plant:

PLT-000003

Observed impact:

- 886 affected orders
- 8 delayed shipments

## Result

FULLY OBSERVED

---

# Scenario 4 — Logistics Disruption

## Objective

Simulate a disruption on a logistics route.

## Propagation

Route disruption
→ transit time increases
→ shipment delay
→ transportation/logistics cost increases
→ ROUTE_DEVIATION events appear
→ IoT telemetry indicates OFF_ROUTE / DELAYED behavior
→ customer fulfillment risk increases

The scenario refers to transportation/logistics cost rather than full landed cost because the generator modifies shipping cost only.

## Final Full Run

Target route:

RTE-000164

Observed impact:

- 47 affected shipments

Route generation is geography-aware using:

- haversine distance
- deterministic route multiplier
- plausible effective transport speed

## Result

FULLY OBSERVED

---

# Scenario 5 — Customer Impact

## Objective

Surface the downstream customer consequence of Scenarios 1–4.

Scenario 5 is not an independent random disruption.

It identifies customer orders already affected by upstream disruption and exposes downstream delivery/service risk.

## Propagation

Supplier / inventory / plant / logistics disruption
→ delayed or partial fulfillment
→ requested delivery date breach
→ customer service deterioration

## Final Full Run

Observed impact:

- 1,500 customers potentially exposed
- 30,322 affected orders
- 30,322 delivery breaches

## Interpretation

Scenario 5 should be treated as a broad cascading-risk / stress-test scenario.

The high percentage of affected orders is intended to demonstrate the platform's ability to trace cascading downstream impact across multiple operational domains rather than represent a typical normal-state delivery-breach rate.

## Result

FULLY OBSERVED

---

# Overall Scenario Status

| Scenario | Status |
|---|---|
| Supplier Deterioration | FULLY OBSERVED |
| Inventory Shortage | FULLY OBSERVED |
| Plant Bottleneck | FULLY OBSERVED |
| Logistics Disruption | FULLY OBSERVED |
| Customer Impact | FULLY OBSERVED |

All scenario effects are encoded through operational data changes rather than explicit scenario flags in production-style tables.