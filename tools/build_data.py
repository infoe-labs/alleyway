#!/usr/bin/env python3
"""Convert OHLCV CSV exports into the game's packed binary market format.

Drop provider CSVs into tools/csv/ (same shape as the original project's exports:
columns date,open,high,low,close,volume; filename SYMBOL_1d_<...>.csv), run
this script, and commit the generated files:

    python3 tools/build_data.py

Outputs, per symbol: game/data/<symbol>.bin plus a shared game/data/manifest.json.

Binary format (little-endian), per bar 24 bytes:
    header: magic 'ABMD', u32 version, u32 bar_count
    bar:    u32 day (Unix epoch days, UTC), f32 open, high, low, close, f32 volume
Bars must be in ascending date order; duplicates are rejected.
"""
from __future__ import annotations

import csv
import json
import re
import struct
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSV_DIR = ROOT / "tools" / "csv"
OUT_DIR = ROOT / "game" / "data"

NAME_RE = re.compile(r"^(?P<symbol>[A-Za-z0-9.\-_]+?)_1d_.*\.csv$")
EPOCH = date(1970, 1, 1)


def parse_csv(path: Path):
    rows = []
    with path.open(newline="") as fh:
        reader = csv.DictReader(fh)
        required = {"date", "open", "high", "low", "close", "volume"}
        if reader.fieldnames is None or not required.issubset(set(reader.fieldnames)):
            sys.exit(f"{path.name}: expected columns {sorted(required)}, got {reader.fieldnames}")
        prev_day = -1
        for lineno, row in enumerate(reader, start=2):
            try:
                d = date.fromisoformat(row["date"].strip()[:10])
                o, h, l, c = (float(row[k]) for k in ("open", "high", "low", "close"))
                v = float(row.get("volume") or 0.0)
            except (ValueError, TypeError, KeyError) as exc:
                sys.exit(f"{path.name}:{lineno}: bad row ({exc})")
            day = (d - EPOCH).days
            if day <= prev_day:
                sys.exit(f"{path.name}:{lineno}: dates must ascend with no duplicates")
            if not (l <= min(o, c) and max(o, c) <= h and l <= h):
                sys.exit(f"{path.name}:{lineno}: OHLC sanity check failed")
            rows.append((day, o, h, l, c, v))
            prev_day = day
    return rows


def main() -> None:
    csvs = sorted(CSV_DIR.glob("*.csv")) if CSV_DIR.is_dir() else []
    if not csvs:
        sys.exit(f"No CSVs found in {CSV_DIR} — drop SYMBOL_1d_*.csv files there first.")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    symbols = []
    for path in csvs:
        m = NAME_RE.match(path.name)
        if not m:
            print(f"skipping {path.name} (expected SYMBOL_1d_*.csv)")
            continue
        symbol = m.group("symbol").upper()
        rows = parse_csv(path)
        if len(rows) < 120:
            sys.exit(f"{path.name}: need at least 120 bars, got {len(rows)}")
        out = OUT_DIR / f"{symbol}.bin"
        with out.open("wb") as fh:
            fh.write(b"ABMD")
            fh.write(struct.pack("<II", 1, len(rows)))
            for day, o, h, l, c, v in rows:
                fh.write(struct.pack("<Ifffff", day, o, h, l, c, v))
        symbols.append(
            {
                "symbol": symbol,
                "file": f"res://data/{symbol}.bin",
                "bars": len(rows),
                "start": str(EPOCH.fromordinal(EPOCH.toordinal() + rows[0][0])),
                "end": str(EPOCH.fromordinal(EPOCH.toordinal() + rows[-1][0])),
            }
        )
        print(f"{symbol}: {len(rows)} bars -> {out.relative_to(ROOT)}")

    manifest = {"format": 1, "symbols": symbols}
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"manifest: {len(symbols)} symbol(s) -> {(OUT_DIR / 'manifest.json').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
