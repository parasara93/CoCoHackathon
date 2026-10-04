"""Run the corrected synthetic generator end-to-end with validation and CDC replay."""
from __future__ import annotations

import argparse
import gc
import shutil
import time
import tracemalloc
from pathlib import Path

from synth_generator import (
    GeneratorConfig, generate_all, baseline_health_metrics,
    validate_scenario_supplier_deterioration,
    validate_scenario_inventory_shortage,
    validate_scenario_plant_bottleneck,
    validate_scenario_logistics_disruption,
    validate_scenario_customer_impact,
)
from csv_output import write_all_csv, validate_csv_output, reconcile_csv_output, replay_csv_output


def _print_scenario_summary(tables):
    meta_specs = [
        ("_scenario_1_meta", "SC1", validate_scenario_supplier_deterioration),
        ("_scenario_2_meta", "SC2", validate_scenario_inventory_shortage),
        ("_scenario_3_meta", "SC3", validate_scenario_plant_bottleneck),
        ("_scenario_4_meta", "SC4", validate_scenario_logistics_disruption),
        ("_scenario_5_meta", "SC5", validate_scenario_customer_impact),
    ]
    print("\n=== Scenario Targets ===")
    for key, label, fn in meta_specs:
        meta = tables.get(key, {})
        parts = []
        for k in ["target_supplier", "target_plant", "target_route"]:
            if k in meta: parts.append(f"{k}={meta[k]}")
        for k in ["affected_part_ids", "affected_plant_ids", "affected_shipment_ids", "affected_order_ids", "affected_inv_keys", "affected_customer_ids"]:
            if k in meta:
                try: n = len(meta[k])
                except Exception: n = 1
                parts.append(f"{k}={n}")
        if label == "SC5":
            n_orders = len(meta.get("affected_order_ids", []))
            total_orders = len(tables.get("orders", []))
            parts.append(f"affected_order_pct={100*n_orders/max(total_orders,1):.1f}%")
        print(f"  {label}: {', '.join(parts)}")

    print("\n=== Scenario Propagation ===")
    all_ok = True
    for key, label, fn in meta_specs:
        if key not in tables: continue
        report = fn(tables)
        result_line = [x for x in report if "Cross-domain propagation:" in x]
        result = result_line[0].strip() if result_line else "UNKNOWN"
        print(f"  {label}: {result}")
        all_ok &= "FULLY" in result
    return all_ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preset", choices=["tiny", "medium", "full"], default="full")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", default="supply-chain-fixed")
    parser.add_argument("--clean", action="store_true")
    args = parser.parse_args()

    out_dir = Path(args.output)
    if args.clean and out_dir.exists(): shutil.rmtree(out_dir)

    tracemalloc.start(); t0 = time.perf_counter(); gc.collect()
    cfg = GeneratorConfig(seed=args.seed, preset=args.preset)
    print(f"Generating preset={args.preset}, seed={args.seed}")
    tables, validation = generate_all(cfg)

    print("\n=== Row Counts ===")
    for name in sorted(tables):
        if name.startswith("_"): continue
        try: print(f"  {name:30s} {len(tables[name]):>10,}")
        except Exception: pass

    print("\n=== Standard + Data Quality Validations ===")
    validation_ok = True
    for k, errs in validation.items():
        print(f"  [{k}] {'PASS' if not errs else 'FAIL'}")
        for e in errs[:20]: print("    -", e)
        validation_ok &= not errs

    print("\n=== Baseline / Dataset Health Metrics ===")
    metrics = baseline_health_metrics(tables)
    for k, v in metrics.items(): print(f"  {k}: {v}")

    scenario_ok = _print_scenario_summary(tables)

    print("\n=== CSV Generation ===")
    stats = write_all_csv(tables, cfg, str(out_dir))
    for k in ["files_total", "files_historical", "files_incremental", "empty_batches"]:
        print(f"  {k}: {stats.get(k)}")

    print("\n=== CSV Validation ===")
    csv_val = validate_csv_output(str(out_dir), tables, cfg)
    csv_ok = not csv_val["errors"]
    print("  ", "PASS" if csv_ok else "FAIL")
    for e in csv_val["errors"][:30]: print("    -", e)
    for w in csv_val["warnings"][:10]: print("    warning:", w)

    print("\n=== Row Reconciliation ===")
    recon = reconcile_csv_output(str(out_dir), tables)
    recon_ok = all(r["status"] == "PASS" for r in recon.values())
    for name, r in sorted(recon.items()):
        print(f"  {name:30s} {r['status']} missing={r.get('missing',0)} unexpected={r.get('unexpected',0)}")

    print("\n=== CDC Replay ===")
    replay = replay_csv_output(str(out_dir), tables)
    replay_ok = all(r["status"] == "PASS" for r in replay.values())
    for name, r in sorted(replay.items()): print(f"  {name:30s} {r['status']} mismatches={r.get('mismatches',0)}")

    elapsed = time.perf_counter() - t0
    _, peak = tracemalloc.get_traced_memory(); tracemalloc.stop()
    print("\n=== Runtime ===")
    print(f"  total_seconds: {elapsed:.1f}")
    print(f"  peak_memory_mb: {peak/1024/1024:.1f}")
    print(f"  output_dir: {out_dir.resolve()}")

    overall = validation_ok and scenario_ok and csv_ok and recon_ok and replay_ok
    print(f"\n=== OVERALL: {'PASS' if overall else 'FAIL'} ===")
    raise SystemExit(0 if overall else 2)


if __name__ == "__main__":
    main()
