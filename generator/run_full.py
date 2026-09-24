"""Full preset runner with aggressive memory management."""
import warnings, sys, traceback, time, tracemalloc, gc
warnings.filterwarnings("ignore")
sys.stdout.reconfigure(line_buffering=True)

tracemalloc.start()
from pathlib import Path
from synth_generator import GeneratorConfig, generate_all
from synth_generator import (
    validate_scenario_supplier_deterioration,
    validate_scenario_inventory_shortage,
    validate_scenario_plant_bottleneck,
    validate_scenario_logistics_disruption,
    validate_scenario_customer_impact,
)
from csv_output import write_all_csv, validate_csv_output, reconcile_csv_output

OUTPUT_DIR = r"c:\Users\heman\OneDrive\Desktop\CoCoHackathon\supply-chain"
t0 = time.perf_counter()

# Force GC before generation
gc.collect()

print("Step 1: generate_all (full preset)...", flush=True)
cfg = GeneratorConfig(seed=42, preset="full")
tables, val = generate_all(cfg)
t_gen = time.perf_counter() - t0
_, pk = tracemalloc.get_traced_memory()
print(f"  Done in {t_gen:.1f}s. Peak: {pk//1024//1024}MB", flush=True)

# Row counts
print("\n=== Row Counts ===")
for name in sorted(tables):
    if name.startswith("_"):
        continue
    df = tables[name]
    if hasattr(df, "__len__"):
        print(f"  {name:30s}  {len(df):>10,}")

# Standard validations
print("\n=== Standard Validations ===")
for k, errs in val.items():
    status = "PASS" if not errs else "FAIL"
    print(f"  [{k}] {status}")
    for e in errs[:10]:
        print(f"    - {e}")
    if len(errs) > 10:
        print(f"    ... and {len(errs) - 10} more")

# Write CSV
gc.collect()
print("\nStep 2: write_all_csv...", flush=True)
t1 = time.perf_counter()
try:
    stats = write_all_csv(tables, cfg, OUTPUT_DIR)
    t_write = time.perf_counter() - t1
    print(f"  Done in {t_write:.1f}s. Files: {stats['files_total']}", flush=True)
except Exception as e:
    traceback.print_exc()
    sys.exit(1)

print(f"\n=== File Generation Summary ===")
print(f"  Total files: {stats['files_total']}")
print(f"  Historical files: {stats['files_historical']}")
print(f"  Incremental files: {stats['files_incremental']}")
print(f"  Empty batches skipped: {stats['empty_batches']}")

print("\n=== Files by Table ===")
for t, c in sorted(stats["files_by_table"].items()):
    ins = stats["rows_insert"].get(t, 0)
    upd = stats["rows_update"].get(t, 0)
    print(f"  {t:30s}  files={c:>4}  inserts={ins:>8,}  updates={upd:>6,}")

# IoT detail
iot_dir = Path(OUTPUT_DIR) / "iot" / "vehicle_telemetry"
if iot_dir.exists():
    import pandas as pd
    all_iot = list(iot_dir.glob("*.csv"))
    hourly_iot = [f for f in all_iot if len(f.stem[len("vehicle_telemetry_"):]) >= 10 and f.stem[len("vehicle_telemetry_"):][:8].isdigit()]
    monthly_iot = [f for f in all_iot if f not in set(hourly_iot)]
    print(f"\n=== IoT File Breakdown ===")
    print(f"  Monthly (historical): {len(monthly_iot)}")
    print(f"  Hourly (incremental): {len(hourly_iot)}")
    if hourly_iot:
        total_rows = 0
        populated = 0
        for f in hourly_iot:
            try:
                n = len(pd.read_csv(f, usecols=["telemetry_id"]))
                total_rows += n
                if n > 0: populated += 1
            except Exception:
                pass
        print(f"  Hourly slots with telemetry: {populated}")
        print(f"  Total incremental telemetry rows: {total_rows:,}")
        print(f"  Avg rows per hourly batch: {total_rows / max(populated, 1):.1f}")

# CSV Validation
gc.collect()
print("\nStep 3: validate_csv_output...", flush=True)
t2 = time.perf_counter()
try:
    val_result = validate_csv_output(OUTPUT_DIR, tables, cfg)
    t_val = time.perf_counter() - t2
    print(f"  Done in {t_val:.1f}s. Errors: {len(val_result['errors'])}", flush=True)
except Exception as e:
    traceback.print_exc()
    sys.exit(1)

if val_result["errors"]:
    print(f"\n=== CSV Validation ERRORS ({len(val_result['errors'])}) ===")
    for e in val_result["errors"][:20]:
        print(f"  - {e}")
else:
    print("\n=== CSV Validation: All passed ===")

# Reconciliation
gc.collect()
print("\nStep 4: reconcile_csv_output...", flush=True)
t3 = time.perf_counter()
try:
    recon = reconcile_csv_output(OUTPUT_DIR, tables)
    t_recon = time.perf_counter() - t3
    print(f"  Done in {t_recon:.1f}s.", flush=True)
except Exception as e:
    traceback.print_exc()
    sys.exit(1)

print("\n=== Row Reconciliation ===")
recon_ok = True
for tname, r in sorted(recon.items()):
    st = r["status"]
    if st != "PASS": recon_ok = False
    supp = r.get("supplemental", 0)
    supp_str = f"  supplemental={supp:>8,}" if supp else ""
    print(
        f"  {tname:30s}  source={r['source_rows']:>10,}  "
        f"file_unique={r['file_unique_inserts']:>10,}{supp_str}  "
        f"missing={r['missing']:>5}  unexpected={r['unexpected']:>5}  "
        f"dup_inserts={r['dup_inserts']:>5}  [{st}]"
    )
if recon_ok:
    print("  All tables reconciled successfully.")
else:
    print("  RECONCILIATION FAILURES — see above.")

# Scenario detail
print("\n=== Scenario Targets ===")
scenario_meta = [
    ("_scenario_1_meta", "S1", validate_scenario_supplier_deterioration),
    ("_scenario_2_meta", "S2", validate_scenario_inventory_shortage),
    ("_scenario_3_meta", "S3", validate_scenario_plant_bottleneck),
    ("_scenario_4_meta", "S4", validate_scenario_logistics_disruption),
    ("_scenario_5_meta", "S5", validate_scenario_customer_impact),
]
for key, label, fn in scenario_meta:
    meta = tables.get(key)
    if not meta: continue
    parts = []
    for k in ["target_supplier","target_plant","target_route"]:
        if k in meta: parts.append(f"{k}={meta[k]}")
    for k in ["target_part_ids","affected_shipment_ids","affected_order_ids","affected_inv_keys","affected_customer_ids"]:
        if k in meta: parts.append(f"{k}={len(meta[k])}")
    for k in ["delivery_breach_count","partial_shipment_count"]:
        if k in meta: parts.append(f"{k}={meta[k]}")
    print(f"  {label}: {', '.join(parts)}")

print("\n=== Scenario Propagation ===")
all_fully = True
for key, label, fn in scenario_meta:
    if key in tables:
        report = fn(tables)
        result_line = [l for l in report if "Cross-domain propagation:" in l]
        status = result_line[0].strip() if result_line else "UNKNOWN"
        print(f"  {label}: {status}")
        if "FULLY" not in status: all_fully = False
if all_fully:
    print("  All 5 scenarios FULLY OBSERVED.")

# Runtime
elapsed = time.perf_counter() - t0
_, peak = tracemalloc.get_traced_memory()
tracemalloc.stop()
print(f"\n=== Runtime & Memory ===")
print(f"  Generation: {t_gen:.1f}s")
print(f"  CSV write: {t_write:.1f}s")
print(f"  CSV validation: {t_val:.1f}s")
print(f"  Reconciliation: {t_recon:.1f}s")
print(f"  Total: {elapsed:.1f}s")
print(f"  Peak memory: {peak / 1024 / 1024:.1f} MB")
print(f"\n=== Fallback Report ===")
print("  Older delivered shipments use reduced telemetry density (per contract Section 9).")
print("\nDone.", flush=True)
