# Plan: Fix Supply-Chain Synthetic Data Generator

## Overview

Repair synth_generator.py, csv_output.py, and run_full.py to fix 21 issues across base generation, scenario injection, CDC/incremental output, and validation. The files are ~2800, ~900, and ~194 lines respectively. Changes are deeply interconnected — generation order, status derivation, and allocation tracking must be coordinated.

## Implementation Strategy

Changes are grouped into 7 phases, each building on the prior. After each phase, run the tiny preset to catch regressions early.

---

## Phase 1: Fix Base Generation Logic (synth_generator.py)

This is the largest and most interconnected phase. The generation order must change because several fixes create new dependencies.

### New generation order in `generate_all()`:
```
1. customers, plants, suppliers, parts, carriers  (reference data — unchanged)
2. routes                                          (FIX #1: direction-constrained)
3. supplier_parts                                  (FIX #2: coverage guarantee)
4. inventory                                       (FIX #3: plant-part assortment first)
5. orders + order_lines                            (FIX #3: plant-aware part selection)
6. shipments + shipment_lines                      (FIX #4+5: status derived from allocation)
7. Back-derive order_line statuses, order statuses (FIX #4: bottom-up status)
8. supplier_performance                            (FIX #7: healthy baseline)
9. shipment_events                                 (FIX #8: organic deviations)
10. vehicle_telemetry                              (FIX #8+9: organic anomalies + deterministic IDs)
```

### Fix #1 — Routes (gen_routes)
- Change route generation to produce weighted distribution:
  - ~40% SUPPLIER→PLANT (INBOUND)
  - ~50% PLANT→CUSTOMER (OUTBOUND)
  - ~10% PLANT→PLANT (TRANSFER)
- Remove CUSTOMER→CUSTOMER combinations
- Set `shipment_type` deterministically from route direction
- Keep haversine distance and transit hour calculations

### Fix #2 — Supplier-Part Coverage (gen_supplier_parts)
- Pass 1: For every part, assign at least one active supplier (round-robin or random)
- Pass 2: Add additional M:M relationships up to `parts_per_supplier_max`
- Enforce exactly one `preferred_supplier_flag=True` per part
- Validate: every part has ≥1 active supplier, exactly 1 preferred

### Fix #3 — Inventory/Demand Consistency
- Generate inventory assortment per plant first (as now)
- Build a lookup: `plant_id → set(part_ids with inventory)`
- In `gen_order_lines`: restrict part selection to parts available in the order's plant's inventory
- This ensures every normal plant+part demand combination has inventory coverage

### Fix #4 — Order/Line Status Derivation
- Generate orders initially as `CREATED` or `CONFIRMED` (early states only)
- Generate order lines with `line_status = PENDING` or similar early state
- After shipment allocation (Fix #5), derive statuses bottom-up:
  - Lines with full shipped_qty → `SHIPPED`/`DELIVERED` (based on shipment status)
  - Lines with partial shipped_qty → `PARTIALLY_SHIPPED`
  - Lines with zero shipment → `CONFIRMED`/`PROCESSING`
  - Cancelled lines → `CANCELLED`
- Derive order_status from aggregate of its line statuses
- Allow ~3-5% random cancellation (order-level or line-level) before shipment allocation

### Fix #5 — Quantity-Safe Shipment Allocation (gen_shipment_lines)
- Maintain `remaining_qty` dict keyed by `order_line_id`
- Initialize: `remaining[ol_id] = ordered_qty`
- For each shipment line: `shipped_qty = min(rng.randint(1, remaining[ol_id]), remaining[ol_id])`
- Deduct: `remaining[ol_id] -= shipped_qty`
- Skip order lines where `remaining[ol_id] <= 0` or `line_status == CANCELLED`
- Validation: `SUM(shipped_qty) <= ordered_qty` per order_line_id

### Fix #6 — Healthy Baseline Logistics (gen_shipments)
- For DELIVERED shipments, generate timing so ~80% are on-time:
  - `actual_delivery_at <= planned_delivery_at` for on-time
  - Small positive offset for the ~20% late
- Departure delays: ~85% on-time or early, ~15% small delays
- Ensure all DELIVERED have both actual_departure_at and actual_delivery_at
- Ensure PICKED_UP/IN_TRANSIT/DELAYED have actual_departure_at

### Fix #7 — Healthy Baseline Supplier Performance
- Partition suppliers into tiers:
  - ~60% healthy (high OTD, low lead time, low risk)
  - ~25% moderate
  - ~15% naturally weak
- Scenario 1 target will come from the healthy pool so deterioration is visible

### Fix #8 — Organic Logistics Events
- In `gen_shipment_events`: add ~2-3% baseline ROUTE_DEVIATION and DELAY_REPORTED events for non-scenario shipments
- In `gen_vehicle_telemetry`: add ~1-2% baseline OFF_ROUTE and DELAYED statuses
- Keep rare enough that Scenario 4 concentration is clearly elevated

### Fix #9 — Deterministic Vehicle IDs
- Replace `hash(sid)` with `hashlib.md5(sid.encode()).hexdigest()` or numeric extraction from shipment_id suffix
- Apply in both synth_generator.py and csv_output.py

---

## Phase 2: Fix Scenario Injection (synth_generator.py)

### Fix #10 — SC1 Supplier Deterioration
- Target a supplier from the healthy tier
- Limit inventory impact to plants that actually use the target supplier's parts
- Ensure deterioration metrics are clearly worse than baseline range

### Fix #11 — SC2 Inventory Shortage (Mixed Severity)
- Instead of all positions → 0, distribute across:
  - ~30% OUT_OF_STOCK (qty=0)
  - ~40% CRITICAL (0 < qty < safety_stock)
  - ~30% LOW (safety_stock < qty < reorder_point)
- Keep downstream order/shipment effects

### Fix #12 — SC3 Plant Bottleneck
- Ensure affected orders/shipments are genuinely associated with the target plant
- Don't accidentally affect unrelated plants' orders

### Fix #13 — SC4 Logistics Disruption
- Keep route deterioration logic
- Scenario must show clearly elevated concentration vs new organic baseline

### Fix #14 — SC5 Customer Impact (Critical)
- Replace current global PROCESSING/delayed union with explicit derivation:
  ```
  affected_orders = SC1.affected_order_ids ∪ SC2.affected_order_ids ∪ SC3.affected_order_ids
                    ∪ orders linked via shipment_lines to SC4.affected_shipment_ids
  ```
- Deduplicate
- Derive affected customers from these orders only
- This prevents SC5 from engulfing the entire order population

---

## Phase 3: Fix Incremental CSV/CDC Generation (csv_output.py)

### Fix #15 — Latest-State Update Tracking
- Maintain `current_state: Dict[tuple_pk, dict_row]` per table
- Initialize from historical data
- Each update: read from `current_state[pk]`, mutate, write back to `current_state[pk]`
- Next batch uses the updated state

### Fix #16 — Valid State Transitions
- Define explicit transition graphs:
  ```python
  ORDER_TRANSITIONS = {
      'CREATED': ['CONFIRMED', 'CANCELLED'],
      'CONFIRMED': ['PROCESSING', 'CANCELLED'],
      'PROCESSING': ['PARTIALLY_SHIPPED', 'SHIPPED', 'CANCELLED'],
      'PARTIALLY_SHIPPED': ['SHIPPED'],
      'SHIPPED': ['DELIVERED'],
      'DELIVERED': [],
      'CANCELLED': [],
  }
  SHIPMENT_TRANSITIONS = {
      'PLANNED': ['PICKED_UP', 'CANCELLED'],
      'PICKED_UP': ['IN_TRANSIT'],
      'IN_TRANSIT': ['DELAYED', 'DELIVERED'],
      'DELAYED': ['IN_TRANSIT', 'DELIVERED'],
      'DELIVERED': [],
      'CANCELLED': [],
  }
  ```
- `_generate_updates()` picks from valid next states only
- Terminal states (DELIVERED, CANCELLED) are never selected for update

### Fix #17 — Shipment Update Timestamps
- When transitioning to PICKED_UP/IN_TRANSIT: set `actual_departure_at` if null
- When transitioning to DELIVERED: set both `actual_departure_at` (if null) and `actual_delivery_at`
- Enforce `actual_delivery_at >= actual_departure_at`

### Fix #18 — Inventory Update Classification
- Add missing LOW state: `safety_stock <= avail < reorder_point`
- Full logic: OUT_OF_STOCK → CRITICAL → LOW → ADEQUATE

### Fix #19 — CDC Metadata Columns
- Add `_ingest_operation` (INSERT/UPDATE) and `_ingest_batch_ts` columns to incremental CSV files
- Historical/base records: INSERT
- Update records: UPDATE
- These are CSV-only fields, not in TABLE_SCHEMAS business columns
- Update CSV validation to handle these extra columns

### Fix #20 — CDC Replay Validator
- New function `validate_cdc_replay(output_dir, tables, cfg)`
- Read all CSV files in chronological order
- Build `current_state[table][pk]` by applying INSERTs and UPDATEs
- Compare final replayed state against expected final state from in-memory tables
- Report PASS/FAIL per mutable table

---

## Phase 4: Add Data Quality Validations (synth_generator.py)

New validation functions:
- `validate_quantity_allocation(tables)` — shipped_qty ≤ ordered_qty
- `validate_cancelled_isolation(tables)` — cancelled lines have no shipment allocations
- `validate_inventory_coverage(tables)` — every demand plant+part in inventory
- `validate_supplier_coverage(tables)` — every part has ≥1 active supplier, 1 preferred
- `validate_route_direction(tables)` — no CUSTOMER→CUSTOMER, shipment_type matches direction
- `validate_shipment_consistency(tables)` — DELIVERED has timestamps, status/timestamp coherence
- `validate_order_consistency(tables)` — order/line status matches fulfillment
- `validate_baseline_health(tables)` — prints metrics (not hard-fail), returns report dict
- `validate_scenario_contrast(tables)` — per-scenario before/after metrics

---

## Phase 5: Update run_full.py and Test Tiny

- Wire all new validators into the execution flow
- Add baseline health metrics section
- Add CDC replay validation section
- Add scenario contrast section
- Run tiny preset, fix all failures

---

## Phase 6: Test Medium Preset

- Run medium preset
- Fix any scale-dependent failures

---

## Phase 7: Test Full Preset and Final Report

- Run `seed=42, preset=full`
- Verify all acceptance criteria pass
- Produce final summary per the required return format

---

## Risk Areas

1. **Generation order change** — Moving status derivation after shipment allocation is the most disruptive change. Must be very careful with the generate_all() orchestration.
2. **Scenario 5 rework** — Completely changes how affected orders are identified. Need to ensure scenarios 1-4 all properly expose their affected_order_ids.
3. **CDC replay** — New validator that reads all CSV files. Performance with full preset (60K shipments) could be slow; may need chunked reading.
4. **Quantity allocation** — Must handle edge cases where all order lines are already fully allocated; shipments may need fewer lines.
