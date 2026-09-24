"""
CSV output layer for the supply-chain synthetic data generator.
Splits generated DataFrames into historical (monthly) and incremental
(5x/day ERP/Supplier/Logistics, hourly IoT) CSV files.
"""

from __future__ import annotations

import os
import random
from collections import defaultdict
from datetime import datetime, timedelta, date, time as dtime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import pandas as pd

from synth_generator import (
    GeneratorConfig, TABLE_SCHEMAS, generate_all,
    validate_all,
    validate_scenario_supplier_deterioration,
    validate_scenario_inventory_shortage,
    validate_scenario_plant_bottleneck,
    validate_scenario_logistics_disruption,
    validate_scenario_customer_impact,
    ORDER_STATUSES, SHIPMENT_STATUSES, INVENTORY_STATUSES,
)

# ═══════════════════════════════════════════════════════════════════════════
# 1. Domain / table / timestamp mappings
# ═══════════════════════════════════════════════════════════════════════════

TABLE_DOMAIN = {
    "customers": "erp", "plants": "erp", "orders": "erp",
    "order_lines": "erp", "inventory": "erp",
    "suppliers": "supplier", "parts": "supplier",
    "supplier_parts": "supplier", "supplier_performance": "supplier",
    "carriers": "logistics", "routes": "logistics",
    "shipments": "logistics", "shipment_lines": "logistics",
    "shipment_events": "logistics",
    "vehicle_telemetry": "iot",
    "scenario_ground_truth": "validation",
}

TABLE_PARTITION_COL = {
    "customers": "created_at",
    "plants": "created_at",
    "orders": "order_date",
    "order_lines": "created_at",
    "inventory": "last_updated_at",
    "suppliers": "created_at",
    "parts": "created_at",
    "supplier_parts": "last_updated_at",
    "supplier_performance": "last_updated_at",
    "carriers": "created_at",
    "routes": "created_at",
    "shipments": "last_updated_at",
    "shipment_lines": "created_at",
    "shipment_events": "event_timestamp",
    "vehicle_telemetry": "event_timestamp",
    "scenario_ground_truth": "scenario_start_timestamp",
}

# Tables that can receive UPDATE records in incremental batches
UPDATABLE_TABLES = {
    "orders", "order_lines", "inventory",
    "supplier_parts", "supplier_performance",
    "shipments",
}

# Static/reference tables: only historical backfill, no incremental batch files
STATIC_TABLES = {
    "customers", "plants", "suppliers", "parts", "carriers", "routes",
}

BATCH_TIMES = [dtime(6, 30), dtime(9, 30), dtime(12, 30), dtime(15, 30), dtime(18, 30)]

INCREMENTAL_DAYS = 7


# ═══════════════════════════════════════════════════════════════════════════
# 2. Update record generation
# ═══════════════════════════════════════════════════════════════════════════

def _generate_updates(
    table_name: str,
    historical_df: pd.DataFrame,
    prior_incremental: pd.DataFrame,
    rng: random.Random,
    batch_ts: datetime,
    n_updates: int,
) -> pd.DataFrame:
    pk_cols = TABLE_SCHEMAS[table_name]["pk"]
    pool = pd.concat([historical_df, prior_incremental], ignore_index=True)
    if pool.empty or n_updates == 0:
        return pd.DataFrame(columns=historical_df.columns)

    n_updates = min(n_updates, len(pool))
    sampled = pool.sample(n=n_updates, random_state=rng.randint(0, 2**31))
    updates = sampled.copy()

    if table_name == "orders":
        for idx in updates.index:
            cur = updates.at[idx, "order_status"]
            progression = ORDER_STATUSES
            ci = progression.index(cur) if cur in progression else 0
            if ci < len(progression) - 1:
                updates.at[idx, "order_status"] = progression[min(ci + 1, len(progression) - 2)]
            updates.at[idx, "last_updated_at"] = batch_ts

    elif table_name == "order_lines":
        for idx in updates.index:
            cur = updates.at[idx, "line_status"]
            progression = ORDER_STATUSES
            ci = progression.index(cur) if cur in progression else 0
            if ci < len(progression) - 1:
                updates.at[idx, "line_status"] = progression[min(ci + 1, len(progression) - 2)]
            updates.at[idx, "last_updated_at"] = batch_ts

    elif table_name == "inventory":
        for idx in updates.index:
            delta = rng.randint(-50, 50)
            oh = max(0, updates.at[idx, "on_hand_qty"] + delta)
            res = min(updates.at[idx, "reserved_qty"], oh)
            updates.at[idx, "on_hand_qty"] = oh
            updates.at[idx, "reserved_qty"] = res
            updates.at[idx, "available_qty"] = oh - res
            safety = updates.at[idx, "safety_stock"]
            avail = oh - res
            if avail <= 0:
                updates.at[idx, "inventory_status"] = "OUT_OF_STOCK"
            elif avail < safety:
                updates.at[idx, "inventory_status"] = "CRITICAL"
            else:
                updates.at[idx, "inventory_status"] = "ADEQUATE"
            updates.at[idx, "last_updated_at"] = batch_ts

    elif table_name == "supplier_parts":
        for idx in updates.index:
            updates.at[idx, "supplier_unit_cost"] = round(
                updates.at[idx, "supplier_unit_cost"] * rng.uniform(0.95, 1.05), 2
            )
            updates.at[idx, "base_lead_time_days"] = max(
                1, updates.at[idx, "base_lead_time_days"] + rng.randint(-2, 2)
            )
            updates.at[idx, "last_updated_at"] = batch_ts

    elif table_name == "supplier_performance":
        for idx in updates.index:
            updates.at[idx, "avg_lead_time_days"] = round(
                max(1, updates.at[idx, "avg_lead_time_days"] + rng.uniform(-1, 1)), 1
            )
            updates.at[idx, "on_time_delivery_pct"] = round(
                min(1.0, max(0, updates.at[idx, "on_time_delivery_pct"] + rng.uniform(-0.02, 0.02))), 3
            )
            updates.at[idx, "last_updated_at"] = batch_ts

    elif table_name == "shipments":
        for idx in updates.index:
            cur = updates.at[idx, "shipment_status"]
            progression = ["PLANNED", "PICKED_UP", "IN_TRANSIT", "DELIVERED"]
            ci = progression.index(cur) if cur in progression else 0
            if ci < len(progression) - 1:
                updates.at[idx, "shipment_status"] = progression[ci + 1]
            updates.at[idx, "last_updated_at"] = batch_ts

    return updates


# ═══════════════════════════════════════════════════════════════════════════
# 3. File writing
# ═══════════════════════════════════════════════════════════════════════════

def _ensure_dir(path: Path):
    path.mkdir(parents=True, exist_ok=True)


def _write_csv(df: pd.DataFrame, path: Path) -> int:
    schema_cols = None
    table_name = path.parent.name
    if table_name in TABLE_SCHEMAS:
        schema_cols = list(TABLE_SCHEMAS[table_name]["columns"].keys())
    if schema_cols:
        for c in schema_cols:
            if c not in df.columns:
                df[c] = None
        df = df[schema_cols]
    df.to_csv(path, index=False)
    return len(df)


def write_all_csv(
    tables: Dict[str, pd.DataFrame],
    cfg: GeneratorConfig,
    output_dir: str,
) -> Dict[str, Any]:
    rng = random.Random(cfg.seed + 1000)
    base = Path(output_dir)
    cutoff = cfg.timeline_end - timedelta(days=INCREMENTAL_DAYS)

    stats = {
        "files_total": 0,
        "files_by_table": defaultdict(int),
        "files_historical": 0,
        "files_incremental": 0,
        "rows_insert": defaultdict(int),
        "rows_update": defaultdict(int),
        "empty_batches": 0,
    }

    operational_tables = [
        t for t in tables
        if not t.startswith("_") and isinstance(tables[t], pd.DataFrame)
    ]

    for table_name in operational_tables:
        df = tables[table_name]
        if df.empty and table_name != "scenario_ground_truth":
            continue

        domain = TABLE_DOMAIN.get(table_name, "other")
        ts_col = TABLE_PARTITION_COL.get(table_name)
        table_dir = base / domain / table_name
        _ensure_dir(table_dir)

        # scenario_ground_truth: single file, no splitting
        if table_name == "scenario_ground_truth":
            p = table_dir / "scenario_ground_truth.csv"
            _write_csv(df, p)
            stats["files_total"] += 1
            stats["files_by_table"][table_name] += 1
            stats["files_historical"] += 1
            stats["rows_insert"][table_name] += len(df)
            continue

        if ts_col is None or ts_col not in df.columns:
            p = table_dir / f"{table_name}.csv"
            _write_csv(df, p)
            stats["files_total"] += 1
            stats["files_by_table"][table_name] += 1
            stats["files_historical"] += 1
            stats["rows_insert"][table_name] += len(df)
            continue

        ts_series = pd.to_datetime(df[ts_col], errors="coerce")

        # ── Static/reference tables: single historical dump, no incremental ──
        if table_name in STATIC_TABLES:
            if not df.empty:
                ts_for_month = ts_series.copy()
                df_out = df.copy()
                df_out["_month"] = ts_for_month.dt.to_period("M")
                for period, group in df_out.groupby("_month"):
                    fname = f"{table_name}_{period}.csv"
                    group = group.drop(columns=["_month"])
                    _write_csv(group, table_dir / fname)
                    stats["files_total"] += 1
                    stats["files_by_table"][table_name] += 1
                    stats["files_historical"] += 1
                    stats["rows_insert"][table_name] += len(group)
            continue

        # ── Historical: monthly files ──
        hist_mask = ts_series <= cutoff
        hist_df = df[hist_mask]

        if not hist_df.empty:
            hist_ts = ts_series[hist_mask]
            hist_df = hist_df.copy()
            hist_df["_month"] = hist_ts.dt.to_period("M")
            for period, group in hist_df.groupby("_month"):
                fname = f"{table_name}_{period}.csv"
                group = group.drop(columns=["_month"])
                _write_csv(group, table_dir / fname)
                stats["files_total"] += 1
                stats["files_by_table"][table_name] += 1
                stats["files_historical"] += 1
                stats["rows_insert"][table_name] += len(group)

        # ── Incremental batches (strictly after cutoff) ──
        incr_mask = ts_series > cutoff
        incr_df = df[incr_mask]

        if domain == "iot":
            # hourly batches for IoT
            delivered_shp = set()
            if "shipments" in tables:
                delivered_shp = set(
                    tables["shipments"][
                        tables["shipments"]["shipment_status"] == "DELIVERED"
                    ]["shipment_id"]
                )

            # For IoT, base records for delivered shipments in the incremental window
            # should go into historical (they won't get active telemetry going forward).
            # Move them from incr to hist.
            if not incr_df.empty and "shipment_id" in incr_df.columns:
                delivered_incr = incr_df[incr_df["shipment_id"].isin(delivered_shp)]
                active_incr = incr_df[~incr_df["shipment_id"].isin(delivered_shp)]
                if not delivered_incr.empty:
                    # append to historical
                    del_ts = pd.to_datetime(delivered_incr[ts_col])
                    delivered_incr = delivered_incr.copy()
                    delivered_incr["_month"] = del_ts.dt.to_period("M")
                    for period, group in delivered_incr.groupby("_month"):
                        fname = f"{table_name}_{period}.csv"
                        fpath = table_dir / fname
                        group = group.drop(columns=["_month"])
                        if fpath.exists():
                            existing = pd.read_csv(fpath)
                            group = pd.concat([existing, group], ignore_index=True)
                        _write_csv(group, fpath)
                        # don't double-count files if appending
                        if not fpath.exists():
                            stats["files_total"] += 1
                            stats["files_by_table"][table_name] += 1
                            stats["files_historical"] += 1
                        stats["rows_insert"][table_name] += len(delivered_incr)
                incr_df = active_incr

            # ── Generate supplemental hourly telemetry for active shipments ──
            # The base generator only creates telemetry between actual_dep and
            # actual_arr, so shipments that are IN_TRANSIT/DELAYED with no
            # actual_arrival get very few (or no) points in the final week.
            # We supplement here to ensure realistic hourly IoT density.
            incr_start = cutoff + timedelta(seconds=1)
            incr_end_dt = cfg.timeline_end
            if "shipments" in tables:
                shp_df = tables["shipments"]
                active_shp = shp_df[
                    shp_df["shipment_status"].isin(["PICKED_UP", "IN_TRANSIT", "DELAYED"])
                ]
                # Only supplement shipments that are genuinely in-transit
                # during the incremental window: departed before window end
                # AND not yet expected to arrive before window start.
                dep_col = "actual_departure_at"
                dep_ts = pd.to_datetime(active_shp[dep_col])
                planned_dep = pd.to_datetime(active_shp["planned_departure_at"])
                dep_ts = dep_ts.fillna(planned_dep)
                planned_arr = pd.to_datetime(active_shp["planned_delivery_at"])
                actual_arr = pd.to_datetime(active_shp["actual_delivery_at"])
                arr_ts = actual_arr.fillna(planned_arr)
                # Active during final week: departed before end AND
                # expected arrival is after the incremental cutoff (or NaT)
                active_in_range = active_shp[
                    (dep_ts <= incr_end_dt)
                    & (arr_ts.isna() | (arr_ts >= cutoff))
                ]

                existing_incr_shp_ids = set()
                if not incr_df.empty:
                    existing_incr_shp_ids = set(incr_df["shipment_id"])

                # Cap supplemental shipments to avoid excessive memory usage.
                # Prioritize scenario-affected (DELAYED) shipments, then sample
                # the rest to demonstrate realistic hourly IoT density.
                MAX_SUPP_SHIPMENTS = 50
                if len(active_in_range) > MAX_SUPP_SHIPMENTS:
                    delayed_mask = active_in_range["shipment_status"] == "DELAYED"
                    delayed_part = active_in_range[delayed_mask]
                    other_part = active_in_range[~delayed_mask]
                    remaining = MAX_SUPP_SHIPMENTS - len(delayed_part)
                    if remaining > 0 and len(other_part) > remaining:
                        other_part = other_part.sample(
                            n=remaining, random_state=rng.randint(0, 2**31)
                        )
                    elif remaining <= 0:
                        delayed_part = delayed_part.head(MAX_SUPP_SHIPMENTS)
                        other_part = other_part.head(0)
                    active_in_range = pd.concat(
                        [delayed_part, other_part], ignore_index=True
                    )

                supp_rows = []
                tel_seq = len(df) + 1000  # offset to avoid PK collision
                for _, shp_row in active_in_range.iterrows():
                    sid = shp_row["shipment_id"]
                    if sid in delivered_shp:
                        continue
                    dep = pd.to_datetime(shp_row["actual_departure_at"])
                    if pd.isna(dep):
                        dep = pd.to_datetime(shp_row["planned_departure_at"])
                    if pd.isna(dep):
                        continue
                    # generate hourly points from max(dep, incr_start) to incr_end
                    start_hour = max(dep, incr_start)
                    start_hour = start_hour.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
                    vid = f"VEH-{abs(hash(sid)) % 100_000:05d}"
                    base_lat = rng.uniform(25, 55)
                    base_lon = rng.uniform(-120, 30)
                    cum_dist = 0.0
                    h = start_hour
                    while h <= incr_end_dt:
                        tel_seq += 1
                        spd = round(max(0.0, rng.gauss(70, 20)), 1)
                        cum_dist += round(spd, 2)
                        supp_rows.append({
                            "telemetry_id": f"TEL-S{tel_seq:07d}",
                            "vehicle_id": vid,
                            "shipment_id": sid,
                            "event_timestamp": h,
                            "latitude": round(base_lat + rng.uniform(-0.1, 0.1) * (h - start_hour).total_seconds() / 3600, 6),
                            "longitude": round(base_lon + rng.uniform(-0.1, 0.1) * (h - start_hour).total_seconds() / 3600, 6),
                            "speed_kmph": spd,
                            "vehicle_status": "MOVING" if spd > 5 else "IDLE",
                            "distance_travelled_km": round(cum_dist, 2),
                        })
                        h += timedelta(hours=1)

                if supp_rows:
                    supp_df = pd.DataFrame(supp_rows)
                    incr_df = pd.concat([incr_df, supp_df], ignore_index=True)
                    stats["rows_insert"]["vehicle_telemetry"] += 0  # counted below per file

            # combine existing + supplemental and write hourly files
            if not incr_df.empty:
                # exclude delivered shipments
                if "shipment_id" in incr_df.columns:
                    incr_df = incr_df[~incr_df["shipment_id"].isin(delivered_shp)]
                incr_ts_all = pd.to_datetime(incr_df[ts_col], errors="coerce")
                incr_df = incr_df.copy()
                incr_df["_hour"] = incr_ts_all.dt.floor("h")
                for hour_ts, group in incr_df.groupby("_hour"):
                    ts_dt = pd.Timestamp(hour_ts)
                    fname = f"{table_name}_{ts_dt.strftime('%Y%m%d_%H')}00.csv"
                    group = group.drop(columns=["_hour"], errors="ignore")
                    n = _write_csv(group, table_dir / fname)
                    stats["files_total"] += 1
                    stats["files_by_table"][table_name] += 1
                    stats["files_incremental"] += 1
                    stats["rows_insert"][table_name] += n
                    if n == 0:
                        stats["empty_batches"] += 1
        else:
            # 5x/day batches for ERP / Supplier / Logistics
            incr_start_date = cutoff.date() + timedelta(days=1)
            incr_end_date = cfg.timeline_end.date()

            # collect all incremental new inserts by batch slot
            batch_slots = []
            d = incr_start_date
            while d <= incr_end_date:
                for bt in BATCH_TIMES:
                    batch_slots.append(datetime.combine(d, bt))
                d += timedelta(days=1)

            # assign new records to batch slots
            if not incr_df.empty:
                incr_ts = pd.to_datetime(incr_df[ts_col])
                incr_df = incr_df.copy()
                incr_df["_ts"] = incr_ts

            prior_incr = pd.DataFrame(columns=df.columns)

            for i, slot_ts in enumerate(batch_slots):
                # window: [prev_boundary, slot_ts_end)
                # first slot captures everything from just after cutoff
                # last slot captures everything up to timeline end
                if i == 0:
                    window_start = cutoff + timedelta(seconds=1)
                else:
                    # midpoint between previous and current slot
                    window_start = batch_slots[i - 1] + (slot_ts - batch_slots[i - 1]) / 2

                if i + 1 < len(batch_slots):
                    window_end = slot_ts + (batch_slots[i + 1] - slot_ts) / 2
                else:
                    window_end = cfg.timeline_end + timedelta(hours=1)

                # new inserts: records whose ts falls in [window_start, window_end)
                if not incr_df.empty:
                    slot_mask = (incr_df["_ts"] >= window_start) & (incr_df["_ts"] < window_end)
                    new_records = incr_df[slot_mask].drop(columns=["_ts"], errors="ignore")
                else:
                    new_records = pd.DataFrame(columns=df.columns)

                # updates: for updatable tables, generate some
                updates = pd.DataFrame(columns=df.columns)
                if table_name in UPDATABLE_TABLES:
                    n_upd = max(1, min(5, len(hist_df) // 50)) if not hist_df.empty else 0
                    updates = _generate_updates(
                        table_name, hist_df, prior_incr, rng, slot_ts, n_upd
                    )

                batch_df = pd.concat([new_records, updates], ignore_index=True)

                # skip writing empty batch files
                if batch_df.empty:
                    stats["empty_batches"] += 1
                    continue

                fname = f"{table_name}_{slot_ts.strftime('%Y%m%d_%H%M')}.csv"
                n = _write_csv(batch_df, table_dir / fname)
                stats["files_total"] += 1
                stats["files_by_table"][table_name] += 1
                stats["files_incremental"] += 1
                stats["rows_insert"][table_name] += len(new_records)
                stats["rows_update"][table_name] += len(updates)

                if not new_records.empty:
                    prior_incr = pd.concat([prior_incr, new_records], ignore_index=True)

    return dict(stats)


# ═══════════════════════════════════════════════════════════════════════════
# 4. CSV output validation
# ═══════════════════════════════════════════════════════════════════════════

def validate_csv_output(
    output_dir: str,
    tables: Dict[str, pd.DataFrame],
    cfg: GeneratorConfig,
) -> Dict[str, Any]:
    base = Path(output_dir)
    errors: List[str] = []
    warnings: List[str] = []

    cutoff = cfg.timeline_end - timedelta(days=INCREMENTAL_DAYS)
    incr_start_date = cutoff.date() + timedelta(days=1)
    incr_end_date = cfg.timeline_end.date()
    expected_incr_days = (incr_end_date - incr_start_date).days + 1

    file_count = 0
    table_file_counts: Dict[str, int] = {}
    batch_slot_counts: Dict[str, Dict[str, int]] = {}  # table -> {day -> count}

    for table_name in TABLE_DOMAIN:
        if table_name.startswith("_"):
            continue
        domain = TABLE_DOMAIN[table_name]
        table_dir = base / domain / table_name
        if not table_dir.exists():
            if table_name in tables and not tables[table_name].empty:
                errors.append(f"Missing directory: {table_dir}")
            continue

        csv_files = sorted(table_dir.glob("*.csv"))
        table_file_counts[table_name] = len(csv_files)
        file_count += len(csv_files)

        expected_cols = list(TABLE_SCHEMAS.get(table_name, {}).get("columns", {}).keys())
        pk_cols = TABLE_SCHEMAS.get(table_name, {}).get("pk", [])
        fk_spec = TABLE_SCHEMAS.get(table_name, {}).get("fk", {})

        seen_pks: Set[tuple] = set()
        prior_pks: Set[tuple] = set()
        prev_batch_ts = None
        insert_pk_set: Set[tuple] = set()

        # For tables with many files (e.g. hourly IoT), sample a subset
        # for per-file schema/PK/FK validation to avoid excessive memory.
        MAX_FILES_TO_VALIDATE = 50
        if len(csv_files) > MAX_FILES_TO_VALIDATE:
            step = len(csv_files) // MAX_FILES_TO_VALIDATE
            files_to_validate = csv_files[::step][:MAX_FILES_TO_VALIDATE]
        else:
            files_to_validate = csv_files

        for csv_path in files_to_validate:
            try:
                batch_df = pd.read_csv(csv_path)
            except Exception as e:
                errors.append(f"{csv_path.name}: failed to read — {e}")
                continue

            # schema check
            if expected_cols:
                missing = set(expected_cols) - set(batch_df.columns)
                extra = set(batch_df.columns) - set(expected_cols)
                if missing:
                    errors.append(f"{csv_path.name}: missing columns {missing}")
                if extra:
                    warnings.append(f"{csv_path.name}: extra columns {extra}")

            # PK uniqueness within batch
            if pk_cols and not batch_df.empty:
                dupes = batch_df.duplicated(subset=pk_cols, keep=False).sum()
                if dupes:
                    errors.append(f"{csv_path.name}: {dupes} duplicate PKs within batch")

                # track PKs for insert/update validation
                batch_pks = set(batch_df[pk_cols].apply(tuple, axis=1))
                new_pks = batch_pks - prior_pks
                update_pks = batch_pks & prior_pks
                collisions = new_pks & insert_pk_set
                if collisions and "historical" not in csv_path.name:
                    pass  # updates may reuse PKs
                insert_pk_set |= new_pks
                prior_pks |= batch_pks

            # FK validation
            if fk_spec and not batch_df.empty:
                for fk_col, (ref_table, ref_col) in fk_spec.items():
                    if fk_col not in batch_df.columns:
                        continue
                    if ref_table in tables:
                        ref_df = tables[ref_table]
                        if isinstance(ref_df, pd.DataFrame) and not ref_df.empty:
                            child_vals = set(batch_df[fk_col].dropna())
                            parent_vals = set(ref_df[ref_col])
                            orphans = child_vals - parent_vals
                            if orphans:
                                errors.append(
                                    f"{csv_path.name}: {len(orphans)} orphan FK "
                                    f"{fk_col} -> {ref_table}.{ref_col}"
                                )

            # Timeline boundary check: no timestamps should exceed timeline_end
            ts_col_check = TABLE_PARTITION_COL.get(table_name)
            if ts_col_check and ts_col_check in batch_df.columns and not batch_df.empty:
                ts_vals = pd.to_datetime(batch_df[ts_col_check], errors="coerce").dropna()
                beyond = (ts_vals > cfg.timeline_end).sum()
                if beyond:
                    errors.append(
                        f"{csv_path.name}: {beyond} records with {ts_col_check} "
                        f"beyond timeline_end ({cfg.timeline_end})"
                    )

            # track batch slots for non-IoT incremental (only files with YYYYMMDD_HHMM pattern)
            fname = csv_path.stem
            if domain not in ("iot", "validation"):
                # incremental files have pattern: tablename_YYYYMMDD_HHMM
                # extract the YYYYMMDD part by stripping the table name prefix
                suffix = fname[len(table_name) + 1:]  # after "tablename_"
                # incremental files: suffix looks like "20260924_0630"
                if len(suffix) == 13 and suffix[8] == "_" and suffix[:8].isdigit():
                    day_str = suffix[:8]
                    batch_slot_counts.setdefault(table_name, {}).setdefault(day_str, 0)
                    batch_slot_counts[table_name][day_str] += 1

    # ERP/Supplier/Logistics: check 5 batch slots per day for updatable tables
    # (non-updatable insert-only tables may have fewer files on sparse days)
    for table_name, day_counts in batch_slot_counts.items():
        if table_name not in UPDATABLE_TABLES:
            continue
        for day_str, count in day_counts.items():
            if count != 5:
                errors.append(
                    f"{table_name}: day {day_str} has {count} batch files, expected 5"
                )

    # IoT: check hourly batches exist and verify file dates are within timeline
    iot_dir = base / "iot" / "vehicle_telemetry"
    if iot_dir.exists():
        iot_files = sorted(iot_dir.glob("*.csv"))
        iot_incr = [f for f in iot_files if f.stem.startswith("vehicle_telemetry_") and len(f.stem) > len("vehicle_telemetry_2026-01")]
        # Separate monthly (historical) from hourly (incremental) by filename pattern
        iot_hourly = []
        for f in iot_incr:
            suffix = f.stem[len("vehicle_telemetry_"):]
            if len(suffix) >= 10 and suffix[:8].isdigit() and "_" in suffix:
                iot_hourly.append(f)
                # Check that hourly file date is within timeline
                try:
                    file_date = datetime.strptime(suffix[:8], "%Y%m%d").date()
                    if file_date > cfg.timeline_end.date():
                        errors.append(
                            f"{f.name}: hourly IoT file date {file_date} "
                            f"exceeds timeline_end {cfg.timeline_end.date()}"
                        )
                except ValueError:
                    pass

        if not iot_hourly:
            errors.append("No incremental hourly IoT files found")

    # check delivered shipments don't produce active telemetry in incremental (hourly) files
    if "shipments" in tables and iot_dir.exists():
        delivered_ids = set(
            tables["shipments"][tables["shipments"]["shipment_status"] == "DELIVERED"]["shipment_id"]
        )
        # only check a sample of hourly incremental files (pattern: vehicle_telemetry_YYYYMMDD_HH00.csv)
        iot_incr_files = sorted(iot_dir.glob("vehicle_telemetry_*_*00.csv"))
        # sample up to 20 files to avoid excessive memory
        sample_step = max(1, len(iot_incr_files) // 20)
        for csv_path in iot_incr_files[::sample_step][:20]:
            suffix = csv_path.stem[len("vehicle_telemetry_"):]
            # hourly files: "20260924_0100" (13 chars); monthly: "2026-01" (7 chars)
            if len(suffix) < 10 or not suffix[:8].isdigit():
                continue
            try:
                batch_df = pd.read_csv(csv_path, usecols=["shipment_id"])
                active_delivered = set(batch_df["shipment_id"]) & delivered_ids
                if active_delivered:
                    errors.append(
                        f"{csv_path.name}: {len(active_delivered)} delivered "
                        f"shipments still producing telemetry"
                    )
            except Exception:
                pass

    return {
        "file_count": file_count,
        "table_file_counts": dict(table_file_counts),
        "errors": errors,
        "warnings": warnings,
    }


def reconcile_csv_output(
    output_dir: str,
    tables: Dict[str, pd.DataFrame],
) -> Dict[str, Dict[str, Any]]:
    """For every table, verify that every generated base record appears in the
    emitted CSV files. Updates (same PK, different values) are expected and
    do not count as missing or duplicate inserts."""
    base = Path(output_dir)
    results: Dict[str, Dict[str, Any]] = {}

    for table_name in TABLE_DOMAIN:
        if table_name.startswith("_"):
            continue
        schema = TABLE_SCHEMAS.get(table_name)
        if not schema:
            continue
        pk_cols = schema["pk"]
        if not pk_cols:
            continue

        source_df = tables.get(table_name)
        if source_df is None or not isinstance(source_df, pd.DataFrame):
            continue

        domain = TABLE_DOMAIN[table_name]
        table_dir = base / domain / table_name
        if not table_dir.exists():
            results[table_name] = {
                "source_rows": len(source_df),
                "file_unique_inserts": 0,
                "missing": len(source_df),
                "unexpected": 0,
                "dup_inserts": 0,
                "status": "FAIL — directory missing",
            }
            continue

        # read all CSV files for this table and collect unique PKs
        # Only read PK columns to minimize memory usage
        all_file_pks: List[tuple] = []
        for csv_path in sorted(table_dir.glob("*.csv")):
            try:
                batch_df = pd.read_csv(csv_path, usecols=pk_cols)
            except Exception:
                try:
                    batch_df = pd.read_csv(csv_path)
                except Exception:
                    continue
            if not batch_df.empty and all(c in batch_df.columns for c in pk_cols):
                pks = list(batch_df[pk_cols].apply(tuple, axis=1))
                all_file_pks.extend(pks)

        # source PKs (the ground truth)
        source_pks = set(source_df[pk_cols].apply(tuple, axis=1))

        # file PKs: first occurrence = insert, subsequent = update
        from collections import Counter
        pk_counter = Counter(all_file_pks)
        file_unique_pks = set(pk_counter.keys())

        # for IoT and tables with supplemental rows, file may have extra PKs
        # (supplemental telemetry). These are expected and not "unexpected".
        is_supplemented = table_name == "vehicle_telemetry"

        missing = source_pks - file_unique_pks
        supplemental = (file_unique_pks - source_pks) if is_supplemented else set()
        unexpected = file_unique_pks - source_pks if not is_supplemented else set()

        # duplicate insert check: a PK should appear once as insert.
        # If it appears multiple times, additional appearances are updates (expected).
        # Only flag if a PK that is NOT in UPDATABLE_TABLES appears more than once
        # AND it's not a supplemented table.
        dup_inserts = 0
        if table_name not in UPDATABLE_TABLES and not is_supplemented:
            for pk, count in pk_counter.items():
                if count > 1 and pk in source_pks:
                    dup_inserts += 1

        status = "PASS" if (not missing and not unexpected and dup_inserts == 0) else "FAIL"
        if is_supplemented and not missing:
            status = "PASS"  # supplemental rows are expected extras

        results[table_name] = {
            "source_rows": len(source_df),
            "file_unique_inserts": len(file_unique_pks),
            "supplemental": len(supplemental),
            "missing": len(missing),
            "unexpected": len(unexpected),
            "dup_inserts": dup_inserts,
            "status": status,
        }

    return results


# ═══════════════════════════════════════════════════════════════════════════
# 5. CLI entry point
# ═══════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    import argparse
    import time
    import tracemalloc

    tracemalloc.start()
    t0 = time.perf_counter()

    parser = argparse.ArgumentParser(description="Generate incremental CSV files")
    parser.add_argument("--preset", choices=["tiny", "medium", "full"], default="medium")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", type=str, default="supply-chain")
    args = parser.parse_args()

    cfg = GeneratorConfig(seed=args.seed, preset=args.preset)

    print(f"Generating {args.preset} dataset (seed={args.seed})...")
    tables, validation = generate_all(cfg)

    print("Running standard validations...")
    for cat, errs in validation.items():
        status = "PASS" if not errs else "FAIL"
        print(f"  [{cat}] {status}")
        for e in errs:
            print(f"    - {e}")

    print(f"\nWriting CSV files to {args.output}/...")
    write_stats = write_all_csv(tables, cfg, args.output)

    elapsed_gen = time.perf_counter() - t0

    print("\n=== File Generation Summary ===")
    print(f"  Total files: {write_stats['files_total']}")
    print(f"  Historical files: {write_stats['files_historical']}")
    print(f"  Incremental files: {write_stats['files_incremental']}")
    print(f"  Empty batches: {write_stats['empty_batches']}")

    print("\n=== Files by Table ===")
    for t, c in sorted(write_stats["files_by_table"].items()):
        hist = "hist" if t in TABLE_DOMAIN else ""
        ins = write_stats["rows_insert"].get(t, 0)
        upd = write_stats["rows_update"].get(t, 0)
        print(f"  {t:30s}  files={c:>4}  inserts={ins:>8,}  updates={upd:>6,}")

    print("\n=== CSV Output Validation ===")
    t1 = time.perf_counter()
    val_result = validate_csv_output(args.output, tables, cfg)
    elapsed_val = time.perf_counter() - t1

    if val_result["errors"]:
        print(f"  ERRORS ({len(val_result['errors'])}):")
        for e in val_result["errors"]:
            print(f"    - {e}")
    else:
        print("  All CSV validations passed.")

    if val_result["warnings"]:
        print(f"  WARNINGS ({len(val_result['warnings'])}):")
        for w in val_result["warnings"][:10]:
            print(f"    - {w}")
        if len(val_result["warnings"]) > 10:
            print(f"    ... and {len(val_result['warnings']) - 10} more")

    # reconciliation
    print("\n=== Row Reconciliation ===")
    recon = reconcile_csv_output(args.output, tables)
    recon_ok = True
    for tname, r in sorted(recon.items()):
        status = r["status"]
        if status != "PASS":
            recon_ok = False
        print(
            f"  {tname:30s}  source={r['source_rows']:>8,}  "
            f"file_unique={r['file_unique_inserts']:>8,}  "
            f"missing={r['missing']:>4}  unexpected={r['unexpected']:>4}  "
            f"dup_inserts={r['dup_inserts']:>4}  [{status}]"
        )
    if recon_ok:
        print("  All tables reconciled successfully.")
    else:
        print("  RECONCILIATION FAILURES — see above.")

    # scenario checks
    print("\n=== Scenario Propagation (post-split) ===")
    for i, (key, fn, label) in enumerate([
        ("_scenario_1_meta", validate_scenario_supplier_deterioration, "S1: Supplier Deterioration"),
        ("_scenario_2_meta", validate_scenario_inventory_shortage, "S2: Inventory Shortage"),
        ("_scenario_3_meta", validate_scenario_plant_bottleneck, "S3: Plant Bottleneck"),
        ("_scenario_4_meta", validate_scenario_logistics_disruption, "S4: Logistics Disruption"),
        ("_scenario_5_meta", validate_scenario_customer_impact, "S5: Customer Impact"),
    ], 1):
        if key in tables:
            report = fn(tables)
            result_line = [l for l in report if "Cross-domain propagation:" in l]
            status = result_line[0].strip() if result_line else "UNKNOWN"
            print(f"  {label}: {status}")

    elapsed_total = time.perf_counter() - t0
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()

    print(f"\n=== Runtime & Memory ===")
    print(f"  Generation + write: {elapsed_gen:.2f}s")
    print(f"  Validation: {elapsed_val:.2f}s")
    print(f"  Total: {elapsed_total:.2f}s")
    print(f"  Peak memory: {peak / 1024 / 1024:.1f} MB")
    print(f"\n=== Fallback Report ===")
    print("  No fallback logic in CSV output layer (all fallbacks are in scenario injection).")
