"""CSV output layer for the supply-chain synthetic data generator.

Produces deterministic monthly historical files plus incremental CDC files:
- ERP / Supplier / Logistics: five slots/day for the final seven days
- IoT: hourly files

Business schemas are unchanged. CSVs add two technical ingestion columns:
_ingest_operation and _ingest_batch_ts.
"""
from __future__ import annotations

import hashlib
import random
from collections import defaultdict
from datetime import datetime, timedelta, time as dtime
from pathlib import Path
from typing import Any, Dict, List, Set, Tuple

import pandas as pd

from synth_generator import (
    GeneratorConfig, TABLE_SCHEMAS,
    validate_scenario_supplier_deterioration,
    validate_scenario_inventory_shortage,
    validate_scenario_plant_bottleneck,
    validate_scenario_logistics_disruption,
    validate_scenario_customer_impact,
)

TABLE_DOMAIN = {
    "customers": "erp", "plants": "erp", "orders": "erp",
    "order_lines": "erp", "inventory": "erp",
    "suppliers": "supplier", "parts": "supplier",
    "supplier_parts": "supplier", "supplier_performance": "supplier",
    "carriers": "logistics", "routes": "logistics",
    "shipments": "logistics", "shipment_lines": "logistics",
    "shipment_events": "logistics", "vehicle_telemetry": "iot",
    "scenario_ground_truth": "validation",
}

TABLE_PARTITION_COL = {
    "customers": "created_at", "plants": "created_at", "orders": "order_date",
    "order_lines": "created_at", "inventory": "last_updated_at",
    "suppliers": "created_at", "parts": "created_at",
    "supplier_parts": "last_updated_at", "supplier_performance": "last_updated_at",
    "carriers": "created_at", "routes": "created_at", "shipments": "last_updated_at",
    "shipment_lines": "created_at", "shipment_events": "event_timestamp",
    "vehicle_telemetry": "event_timestamp", "scenario_ground_truth": "scenario_start_timestamp",
}

UPDATABLE_TABLES = {
    "orders", "order_lines", "inventory", "supplier_parts",
    "supplier_performance", "shipments",
}
STATIC_TABLES = {"customers", "plants", "suppliers", "parts", "carriers", "routes"}
APPEND_ONLY_TABLES = {"shipment_lines", "shipment_events", "vehicle_telemetry"}
BATCH_TIMES = [dtime(6, 30), dtime(9, 30), dtime(12, 30), dtime(15, 30), dtime(18, 30)]
INCREMENTAL_DAYS = 7
META_COLS = ["_ingest_operation", "_ingest_batch_ts"]


def _stable_vehicle_id(shipment_id: str) -> str:
    digest = hashlib.sha256(str(shipment_id).encode("utf-8")).hexdigest()
    return f"VEH-{int(digest[:12], 16) % 100_000:05d}"


def _ensure_dir(path: Path):
    path.mkdir(parents=True, exist_ok=True)


def _with_meta(df: pd.DataFrame, operation: str, batch_ts: datetime) -> pd.DataFrame:
    out = df.copy()
    out["_ingest_operation"] = operation
    out["_ingest_batch_ts"] = batch_ts
    return out


def _write_csv(df: pd.DataFrame, path: Path) -> int:
    table_name = path.parent.name
    schema_cols = list(TABLE_SCHEMAS.get(table_name, {}).get("columns", {}).keys())
    cols = schema_cols + [c for c in META_COLS if c in df.columns]
    out = df.copy()
    for c in schema_cols:
        if c not in out.columns:
            out[c] = None
    if cols:
        out = out[cols]
    out.to_csv(path, index=False)
    return len(out)


def _inventory_status(avail: float, safety: float, reorder: float) -> str:
    if avail <= 0: return "OUT_OF_STOCK"
    if avail < safety: return "CRITICAL"
    if avail < reorder: return "LOW"
    return "ADEQUATE"


def _make_prior_version(table_name: str, row: pd.Series, rng: random.Random) -> pd.Series:
    """Create a plausible earlier state. The emitted UPDATE later restores row exactly."""
    r = row.copy()
    if table_name == "orders":
        prev = {"DELIVERED": "SHIPPED", "SHIPPED": "PARTIALLY_SHIPPED",
                "PARTIALLY_SHIPPED": "PROCESSING", "PROCESSING": "CONFIRMED"}
        r["order_status"] = prev.get(str(r["order_status"]), r["order_status"])
    elif table_name == "order_lines":
        prev = {"DELIVERED": "SHIPPED", "SHIPPED": "PARTIALLY_SHIPPED",
                "PARTIALLY_SHIPPED": "PROCESSING", "PROCESSING": "CONFIRMED"}
        r["line_status"] = prev.get(str(r["line_status"]), r["line_status"])
    elif table_name == "inventory":
        delta = rng.randint(10, 80)
        r["on_hand_qty"] = max(0, int(r["on_hand_qty"]) + delta)
        r["available_qty"] = int(r["on_hand_qty"]) - int(r["reserved_qty"])
        r["inventory_status"] = _inventory_status(r["available_qty"], r["safety_stock"], r["reorder_point"])
    elif table_name == "supplier_parts":
        r["supplier_unit_cost"] = round(float(r["supplier_unit_cost"]) * rng.uniform(0.96, 1.04), 2)
        r["base_lead_time_days"] = max(1, int(r["base_lead_time_days"]) + rng.choice([-1, 1]))
    elif table_name == "supplier_performance":
        r["avg_lead_time_days"] = round(max(1.0, float(r["avg_lead_time_days"]) + rng.uniform(-1.0, 1.0)), 1)
        r["on_time_delivery_pct"] = round(min(1.0, max(0.0, float(r["on_time_delivery_pct"]) + rng.uniform(-0.02, 0.02))), 3)
    elif table_name == "shipments":
        prev = {"DELIVERED": "IN_TRANSIT", "IN_TRANSIT": "PICKED_UP", "DELAYED": "IN_TRANSIT", "PICKED_UP": "PLANNED"}
        prior = prev.get(str(r["shipment_status"]), r["shipment_status"])
        r["shipment_status"] = prior
        if prior == "PLANNED":
            r["actual_departure_at"] = None; r["actual_delivery_at"] = None
        elif prior in ("PICKED_UP", "IN_TRANSIT", "DELAYED"):
            r["actual_delivery_at"] = None
    return r


def _batch_slots(cfg: GeneratorConfig) -> List[datetime]:
    cutoff = cfg.timeline_end - timedelta(days=INCREMENTAL_DAYS)
    d = cutoff.date() + timedelta(days=1)
    slots: List[datetime] = []
    while d <= cfg.timeline_end.date():
        slots.extend(datetime.combine(d, t) for t in BATCH_TIMES)
        d += timedelta(days=1)
    return slots


def _slot_for_timestamp(ts: pd.Timestamp, slots: List[datetime]) -> datetime:
    if not slots:
        raise ValueError("No incremental slots")
    value = pd.Timestamp(ts).to_pydatetime()
    for slot in slots:
        if value <= slot:
            return slot
    return slots[-1]


def write_all_csv(tables: Dict[str, pd.DataFrame], cfg: GeneratorConfig, output_dir: str) -> Dict[str, Any]:
    rng = random.Random(cfg.seed + 1000)
    base = Path(output_dir)
    cutoff = cfg.timeline_end - timedelta(days=INCREMENTAL_DAYS)
    slots = _batch_slots(cfg)
    stats = {
        "files_total": 0, "files_by_table": defaultdict(int),
        "files_historical": 0, "files_incremental": 0,
        "rows_insert": defaultdict(int), "rows_update": defaultdict(int),
        "empty_batches": 0,
    }

    for table_name, df0 in tables.items():
        if table_name.startswith("_") or not isinstance(df0, pd.DataFrame):
            continue
        df = df0.copy()
        domain = TABLE_DOMAIN.get(table_name, "other")
        table_dir = base / domain / table_name
        _ensure_dir(table_dir)

        if table_name == "scenario_ground_truth":
            p = table_dir / "scenario_ground_truth.csv"
            _write_csv(_with_meta(df, "INSERT", cfg.timeline_start), p)
            stats["files_total"] += 1; stats["files_by_table"][table_name] += 1; stats["files_historical"] += 1
            stats["rows_insert"][table_name] += len(df)
            continue

        ts_col = TABLE_PARTITION_COL.get(table_name)
        if not ts_col or ts_col not in df.columns:
            p = table_dir / f"{table_name}.csv"
            _write_csv(_with_meta(df, "INSERT", cfg.timeline_start), p)
            stats["files_total"] += 1; stats["files_by_table"][table_name] += 1; stats["files_historical"] += 1
            stats["rows_insert"][table_name] += len(df)
            continue

        ts = pd.to_datetime(df[ts_col], errors="coerce")

        # Static dimensions are historical-only monthly inserts.
        if table_name in STATIC_TABLES:
            tmp = df.copy(); tmp["_month"] = ts.dt.to_period("M")
            for period, grp in tmp.groupby("_month"):
                grp = grp.drop(columns=["_month"])
                _write_csv(_with_meta(grp, "INSERT", cfg.timeline_start), table_dir / f"{table_name}_{period}.csv")
                stats["files_total"] += 1; stats["files_by_table"][table_name] += 1; stats["files_historical"] += 1
                stats["rows_insert"][table_name] += len(grp)
            continue

        hist_mask = ts <= cutoff
        incr_mask = ts > cutoff
        hist_final = df[hist_mask].copy()
        incr = df[incr_mask].copy()

        # Create deterministic prior versions for a limited set of historical mutable rows.
        update_schedule: Dict[datetime, List[pd.Series]] = defaultdict(list)
        hist_emit = hist_final.copy()
        if table_name in UPDATABLE_TABLES and not hist_final.empty and slots:
            max_targets = min(len(hist_final), max(len(slots), min(len(hist_final), len(slots) * 5)))
            target_idx = hist_final.sample(n=max_targets, random_state=cfg.seed + sum(map(ord, table_name))).index.tolist()
            for j, idx in enumerate(target_idx):
                hist_emit.loc[idx] = _make_prior_version(table_name, hist_final.loc[idx], rng)
                update_schedule[slots[j % len(slots)]].append(hist_final.loc[idx].copy())

        if not hist_emit.empty:
            hist_tmp = hist_emit.copy(); hist_tmp["_month"] = pd.to_datetime(hist_tmp[ts_col], errors="coerce").dt.to_period("M")
            for period, grp in hist_tmp.groupby("_month"):
                grp = grp.drop(columns=["_month"])
                _write_csv(_with_meta(grp, "INSERT", cfg.timeline_start), table_dir / f"{table_name}_{period}.csv")
                stats["files_total"] += 1; stats["files_by_table"][table_name] += 1; stats["files_historical"] += 1
                stats["rows_insert"][table_name] += len(grp)

        if domain == "iot":
            if not incr.empty:
                tmp = incr.copy(); tmp["_hour"] = pd.to_datetime(tmp[ts_col], errors="coerce").dt.floor("h")
                for hour, grp in tmp.groupby("_hour"):
                    if pd.isna(hour): continue
                    grp = grp.drop(columns=["_hour"])
                    fname = f"{table_name}_{pd.Timestamp(hour).strftime('%Y%m%d_%H')}00.csv"
                    _write_csv(_with_meta(grp, "INSERT", pd.Timestamp(hour).to_pydatetime()), table_dir / fname)
                    stats["files_total"] += 1; stats["files_by_table"][table_name] += 1; stats["files_incremental"] += 1
                    stats["rows_insert"][table_name] += len(grp)
            continue

        # Assign final-week inserts to five daily slots.
        inserts_by_slot: Dict[datetime, pd.DataFrame] = {}
        if not incr.empty:
            temp = incr.copy(); temp["__slot"] = pd.to_datetime(temp[ts_col], errors="coerce").apply(lambda x: _slot_for_timestamp(x, slots))
            inserts_by_slot = {slot: grp.drop(columns=["__slot"]) for slot, grp in temp.groupby("__slot")}

        for slot in slots:
            pieces: List[pd.DataFrame] = []
            ins = inserts_by_slot.get(slot)
            if ins is not None and not ins.empty:
                pieces.append(_with_meta(ins, "INSERT", slot)); stats["rows_insert"][table_name] += len(ins)
            updates = update_schedule.get(slot, [])
            if updates:
                upd = pd.DataFrame(updates)
                pieces.append(_with_meta(upd, "UPDATE", slot)); stats["rows_update"][table_name] += len(upd)
            if not pieces:
                stats["empty_batches"] += 1
                continue
            batch = pd.concat(pieces, ignore_index=True)
            # A PK should not appear twice in the same batch; UPDATE wins.
            pk = TABLE_SCHEMAS[table_name]["pk"]
            if pk:
                batch["__op_rank"] = batch["_ingest_operation"].map({"INSERT": 0, "UPDATE": 1})
                batch = batch.sort_values("__op_rank").drop_duplicates(subset=pk, keep="last").drop(columns=["__op_rank"])
            fname = f"{table_name}_{slot.strftime('%Y%m%d_%H%M')}.csv"
            _write_csv(batch, table_dir / fname)
            stats["files_total"] += 1; stats["files_by_table"][table_name] += 1; stats["files_incremental"] += 1

    return dict(stats)


def _csv_files_in_replay_order(table_dir: Path, table_name: str) -> List[Path]:
    monthly: List[Path] = []; incremental: List[Path] = []; other: List[Path] = []
    for p in table_dir.glob("*.csv"):
        suffix = p.stem[len(table_name) + 1:] if p.stem.startswith(table_name + "_") else ""
        if len(suffix) == 7 and suffix[4] == "-": monthly.append(p)
        elif len(suffix) >= 13 and suffix[:8].isdigit() and suffix[8] == "_": incremental.append(p)
        else: other.append(p)
    return sorted(monthly) + sorted(other) + sorted(incremental)


def replay_csv_output(output_dir: str, tables: Dict[str, pd.DataFrame]) -> Dict[str, Dict[str, Any]]:
    """Replay INSERT/UPDATE files by ingestion sequence and compare latest state to expected."""
    base = Path(output_dir); results: Dict[str, Dict[str, Any]] = {}
    for table_name in TABLE_DOMAIN:
        expected = tables.get(table_name)
        if expected is None or not isinstance(expected, pd.DataFrame): continue
        table_dir = base / TABLE_DOMAIN[table_name] / table_name
        pk = TABLE_SCHEMAS[table_name]["pk"]
        if not table_dir.exists():
            results[table_name] = {"status": "FAIL", "mismatches": len(expected), "detail": "directory missing"}; continue
        state: Dict[Tuple[Any, ...], Dict[str, Any]] = {}
        for path in _csv_files_in_replay_order(table_dir, table_name):
            df = pd.read_csv(path)
            if df.empty: continue
            for _, row in df.iterrows():
                key = tuple(row[c] for c in pk)
                business = {c: row.get(c) for c in TABLE_SCHEMAS[table_name]["columns"]}
                state[key] = business
        exp_keys = set(expected[pk].apply(tuple, axis=1)) if not expected.empty else set()
        got_keys = set(state)
        missing = exp_keys - got_keys; unexpected = got_keys - exp_keys
        mismatch = 0
        if not missing and not unexpected:
            exp_idx = expected.set_index(pk)
            for key in exp_keys:
                er = exp_idx.loc[key if len(pk) > 1 else key[0]]
                gr = state[key]
                for col, typ in TABLE_SCHEMAS[table_name]["columns"].items():
                    if col in pk:
                        continue
                    ev = er[col]; gv = gr[col]
                    if typ in ("TIMESTAMP", "DATE"):
                        evn = pd.to_datetime(ev, errors="coerce"); gvn = pd.to_datetime(gv, errors="coerce")
                        if pd.isna(evn) and pd.isna(gvn): continue
                        if evn != gvn: mismatch += 1; break
                    elif typ == "BOOLEAN":
                        # CSV bool normalization
                        es = str(ev).lower(); gs = str(gv).lower()
                        if es not in (gs, "1" if gs == "true" else "0"): mismatch += 1; break
                    elif (pd.isna(ev) and pd.isna(gv)) or (str(ev) == "" and pd.isna(gv)):
                        continue
                    else:
                        # Numeric/string tolerant comparison after CSV serialization.
                        try:
                            if typ == "NUMBER" and abs(float(ev) - float(gv)) <= 1e-6: continue
                        except Exception: pass
                        if str(ev) != str(gv): mismatch += 1; break
        status = "PASS" if not missing and not unexpected and mismatch == 0 else "FAIL"
        results[table_name] = {"status": status, "missing": len(missing), "unexpected": len(unexpected), "mismatches": mismatch}
    return results


def validate_csv_output(output_dir: str, tables: Dict[str, pd.DataFrame], cfg: GeneratorConfig) -> Dict[str, Any]:
    base = Path(output_dir); errors: List[str] = []; warnings: List[str] = []
    file_count = 0; table_file_counts: Dict[str, int] = {}
    for table_name, domain in TABLE_DOMAIN.items():
        table_dir = base / domain / table_name
        expected = tables.get(table_name)
        if not table_dir.exists():
            if isinstance(expected, pd.DataFrame) and not expected.empty: errors.append(f"Missing directory: {table_dir}")
            continue
        files = sorted(table_dir.glob("*.csv")); file_count += len(files); table_file_counts[table_name] = len(files)
        schema_cols = set(TABLE_SCHEMAS[table_name]["columns"]); pk = TABLE_SCHEMAS[table_name]["pk"]
        for path in files:
            try: df = pd.read_csv(path)
            except Exception as e:
                errors.append(f"{path.name}: failed to read: {e}"); continue
            missing_cols = schema_cols - set(df.columns)
            extras = set(df.columns) - schema_cols - set(META_COLS)
            if missing_cols: errors.append(f"{path.name}: missing columns {sorted(missing_cols)}")
            if extras: warnings.append(f"{path.name}: extra columns {sorted(extras)}")
            if "_ingest_operation" not in df.columns or "_ingest_batch_ts" not in df.columns:
                errors.append(f"{path.name}: missing CDC metadata columns")
            elif not set(df["_ingest_operation"].dropna().unique()).issubset({"INSERT", "UPDATE"}):
                errors.append(f"{path.name}: invalid _ingest_operation")
            if pk and not df.empty and df.duplicated(subset=pk).any():
                errors.append(f"{path.name}: duplicate PK within batch")
    replay = replay_csv_output(output_dir, tables)
    for t, r in replay.items():
        if r["status"] != "PASS": errors.append(f"CDC replay {t}: {r}")
    return {"file_count": file_count, "table_file_counts": table_file_counts, "errors": errors, "warnings": warnings, "replay": replay}


def reconcile_csv_output(output_dir: str, tables: Dict[str, pd.DataFrame]) -> Dict[str, Dict[str, Any]]:
    replay = replay_csv_output(output_dir, tables)
    out: Dict[str, Dict[str, Any]] = {}
    for table_name, r in replay.items():
        source = tables[table_name]
        out[table_name] = {
            "source_rows": len(source), "file_unique_inserts": len(source) - r.get("missing", 0),
            "supplemental": r.get("unexpected", 0), "missing": r.get("missing", 0),
            "unexpected": r.get("unexpected", 0), "dup_inserts": 0, "status": r["status"],
        }
    return out


if __name__ == "__main__":
    import argparse
    from synth_generator import generate_all
    parser = argparse.ArgumentParser(description="Generate replayable incremental CSV files")
    parser.add_argument("--preset", choices=["tiny", "medium", "full"], default="medium")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", type=str, default="supply-chain")
    args = parser.parse_args()
    cfg = GeneratorConfig(seed=args.seed, preset=args.preset)
    tables, validation = generate_all(cfg)
    print("Validation:")
    for k, errs in validation.items(): print(f"  {k}: {'PASS' if not errs else 'FAIL'}", *errs[:5], sep="\n    ")
    stats = write_all_csv(tables, cfg, args.output)
    print(stats)
    vr = validate_csv_output(args.output, tables, cfg)
    print(f"CSV validation: {'PASS' if not vr['errors'] else 'FAIL'}")
    for e in vr["errors"][:20]: print(" -", e)
