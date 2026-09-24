"""Medium preset validation runner."""
import warnings, sys, traceback, time
warnings.filterwarnings("ignore")
sys.stdout.reconfigure(line_buffering=True)

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

print("Step 1: generate_all...", flush=True)
cfg = GeneratorConfig(seed=42, preset="medium")
tables, val = generate_all(cfg)
print(f"  Done. Tables: {len(tables)}", flush=True)

print("\n=== Standard Validations ===")
for k, errs in val.items():
    status = "PASS" if not errs else "FAIL"
    print(f"  [{k}] {status}")
    for e in errs:
        print(f"    - {e}")

print("\nStep 2: write_all_csv...", flush=True)
try:
    stats = write_all_csv(tables, cfg, OUTPUT_DIR)
    print(f"  Done. Files: {stats['files_total']}", flush=True)
except Exception as e:
    traceback.print_exc()
    sys.exit(1)

print("\n=== File Generation Summary ===")
print(f"  Total files: {stats['files_total']}")
print(f"  Historical files: {stats['files_historical']}")
print(f"  Incremental files: {stats['files_incremental']}")
print(f"  Empty batches skipped: {stats['empty_batches']}")

print("\n=== Files by Table ===")
for t, c in sorted(stats["files_by_table"].items()):
    ins = stats["rows_insert"].get(t, 0)
    upd = stats["rows_update"].get(t, 0)
    print(f"  {t:30s}  files={c:>4}  inserts={ins:>8,}  updates={upd:>6,}")

# IoT hourly file count
iot_dir = Path(OUTPUT_DIR) / "iot" / "vehicle_telemetry"
if iot_dir.exists():
    all_iot = list(iot_dir.glob("*.csv"))
    monthly_iot = [f for f in all_iot if len(f.stem.split("_")[-1]) <= 2 or "-" in f.stem.split("_")[-1]]
    hourly_iot = [f for f in all_iot if f not in set(monthly_iot)]
    # more reliable: check filename pattern
    hourly_iot = []
    monthly_iot = []
    for f in all_iot:
        suffix = f.stem[len("vehicle_telemetry_"):]
        if len(suffix) >= 10 and suffix[:8].isdigit() and "_" in suffix:
            hourly_iot.append(f)
        else:
            monthly_iot.append(f)

    print(f"\n=== IoT File Breakdown ===")
    print(f"  Monthly (historical): {len(monthly_iot)}")
    print(f"  Hourly (incremental): {len(hourly_iot)}")

    # hourly slot stats
    if hourly_iot:
        import pandas as pd
        hourly_rows = []
        for f in hourly_iot:
            try:
                n = len(pd.read_csv(f))
                hourly_rows.append(n)
            except Exception:
                hourly_rows.append(0)
        total_rows = sum(hourly_rows)
        populated = sum(1 for r in hourly_rows if r > 0)
        avg_per_batch = total_rows / max(populated, 1)
        print(f"  Hourly slots with telemetry: {populated}")
        print(f"  Total incremental telemetry rows: {total_rows:,}")
        print(f"  Avg rows per populated hourly batch: {avg_per_batch:.1f}")

print("\nStep 3: validate_csv_output...", flush=True)
try:
    val_result = validate_csv_output(OUTPUT_DIR, tables, cfg)
    print(f"  Done. Errors: {len(val_result['errors'])}", flush=True)
except Exception as e:
    traceback.print_exc()
    sys.exit(1)

if val_result["errors"]:
    print(f"\n=== CSV Validation ERRORS ({len(val_result['errors'])}) ===")
    for e in val_result["errors"]:
        print(f"  - {e}")
else:
    print("\n=== CSV Validation: All passed ===")

if val_result.get("warnings"):
    print(f"\n  Warnings: {len(val_result['warnings'])}")
    for w in val_result["warnings"][:5]:
        print(f"    - {w}")

print("\nStep 4: reconcile_csv_output...", flush=True)
try:
    recon = reconcile_csv_output(OUTPUT_DIR, tables)
    print(f"  Done. Tables: {len(recon)}", flush=True)
except Exception as e:
    traceback.print_exc()
    sys.exit(1)

print("\n=== Row Reconciliation ===")
recon_ok = True
for tname, r in sorted(recon.items()):
    st = r["status"]
    if st != "PASS":
        recon_ok = False
    supp = r.get("supplemental", 0)
    supp_str = f"  supplemental={supp:>6,}" if supp else ""
    print(
        f"  {tname:30s}  source={r['source_rows']:>8,}  "
        f"file_unique={r['file_unique_inserts']:>8,}{supp_str}  "
        f"missing={r['missing']:>4}  unexpected={r['unexpected']:>4}  "
        f"dup_inserts={r['dup_inserts']:>4}  [{st}]"
    )
if recon_ok:
    print("  All tables reconciled successfully.")
else:
    print("  RECONCILIATION FAILURES — see above.")

print("\n=== Scenario Propagation ===")
for key, fn, label in [
    ("_scenario_1_meta", validate_scenario_supplier_deterioration, "S1: Supplier Deterioration"),
    ("_scenario_2_meta", validate_scenario_inventory_shortage, "S2: Inventory Shortage"),
    ("_scenario_3_meta", validate_scenario_plant_bottleneck, "S3: Plant Bottleneck"),
    ("_scenario_4_meta", validate_scenario_logistics_disruption, "S4: Logistics Disruption"),
    ("_scenario_5_meta", validate_scenario_customer_impact, "S5: Customer Impact"),
]:
    if key in tables:
        report = fn(tables)
        result_line = [l for l in report if "Cross-domain propagation:" in l]
        status = result_line[0].strip() if result_line else "UNKNOWN"
        print(f"  {label}: {status}")

elapsed = time.perf_counter() - t0
print(f"\n=== Runtime ===")
print(f"  Total: {elapsed:.1f}s")
print("\nDone.", flush=True)
