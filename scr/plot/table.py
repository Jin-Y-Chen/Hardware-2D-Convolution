#!/usr/bin/env python3
"""Scan log/vsyn.log and upsert data/part/<top>.csv."""
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
LOG = ROOT / "log" / "vsyn.log"
PART = ROOT / "data" / "part"

COLS = [
    "design", "width", "accw", "period_ns", "freq_mhz",
    "area_um2", "dyn_mw", "leak_uw", "total_mw",
    "slack_ns", "met", "path_start", "path_end", "timing",
]

ALIAS = {
    "WIDTH": "width", "ACCW": "accw", "freq_MHz": "freq_mhz",
    "dyn_mW": "dyn_mw", "leak_uW": "leak_uw", "power_mW": "dyn_mw",
}

try:
    import pandas as pd
except ImportError:
    pd = None


def num(s):
    try:
        v = float(s)
    except (TypeError, ValueError):
        return None
    if v != v:
        return None
    return v


def fmt(v):
    n = num(v)
    if n is not None:
        return f"{n:.6g}"
    if v is None or v == "":
        return ""
    s = str(v)
    return "" if s in ("nan", "None", "<NA>") else s


def first(pat, src):
    m = re.search(pat, src)
    return m.group(1).strip() if m else ""


def parse_log(text: str) -> dict:
    design = first(r'set TOP_MOD_NAME\s+"([^"]+)"', text)
    width = num(first(r"set P_WIDTH\s+(\S+);", text))
    accw = num(first(r"set P_ACCW\s+(\S+);", text))
    period = num(first(r"set CLK_PERIOD\s+(\S+);", text))
    area = num(first(r"Total cell area:\s+([0-9.]+)", text))
    dyn = num(first(r"Total Dynamic Power\s+=\s+([0-9.]+)\s*mW", text))
    leak = num(first(r"Cell Leakage Power\s+=\s+([0-9.]+)\s*uW", text))

    timing_blk = text.split("report_timing -loops", 1)[0]
    start = re.search(r"Startpoint:\s+(\S+)", timing_blk)
    end = re.search(r"Endpoint:\s+(\S+)", timing_blk)
    slack_m = re.search(r"slack \((MET|VIOLATED)\)\s+(-?[0-9.]+)", timing_blk)
    timing_s = slack_m.group(1) if slack_m else ""
    slack = num(slack_m.group(2) if slack_m else None)

    freq = (1000.0 / period) if period else None
    total = None
    if dyn is not None and leak is not None:
        total = dyn + leak / 1000.0
    met = 1 if timing_s == "MET" else 0

    return {
        "design": design,
        "width": fmt(width),
        "accw": fmt(accw),
        "period_ns": fmt(period),
        "freq_mhz": fmt(freq),
        "area_um2": fmt(area),
        "dyn_mw": fmt(dyn),
        "leak_uw": fmt(leak),
        "total_mw": fmt(total),
        "slack_ns": fmt(slack),
        "met": str(met),
        "path_start": start.group(1) if start else "",
        "path_end": end.group(1) if end else "",
        "timing": timing_s,
    }


def _normalize(rec: dict) -> dict:
    rec = {ALIAS.get(k, k): rec[k] for k in rec if k}
    out = {c: fmt(rec.get(c, "")) for c in COLS}
    if not out["total_mw"]:
        d, l = num(rec.get("dyn_mw")), num(rec.get("leak_uw"))
        out["total_mw"] = fmt(d + l / 1000.0) if d is not None and l is not None else ""
    if not out["met"]:
        out["met"] = "1" if out["timing"] == "MET" else "0"
    m = num(out["met"])
    out["met"] = str(int(m)) if m is not None else "0"
    return out


def _key(r: dict):
    return (r.get("design", ""), r.get("width", ""), r.get("accw", ""), r.get("period_ns", ""))


def _sort_key(r: dict):
    return (
        r.get("design") or "",
        num(r.get("width")) or 0,
        num(r.get("accw")) or 0,
        -(num(r.get("period_ns")) or 0),
    )


def load_rows(path: Path) -> list:
    if not path.is_file() or not path.read_text(encoding="utf-8", errors="replace").strip():
        return []
    if pd is not None:
        df = pd.read_csv(path)
        return [_normalize(r) for r in df.to_dict(orient="records")]
    sample = path.read_text(encoding="utf-8", errors="replace").splitlines()[0]
    dialect = "excel" if "," in sample else "excel-tab"
    with path.open(encoding="utf-8", errors="replace", newline="") as f:
        return [_normalize(rec) for rec in csv.DictReader(f, dialect=dialect)]


def upsert(path: Path, row: dict) -> list:
    key = _key(row)
    rows = [r for r in load_rows(path) if _key(r) != key]
    rows.append(row)
    rows.sort(key=_sort_key)
    path.parent.mkdir(parents=True, exist_ok=True)
    if pd is not None:
        df = pd.DataFrame(rows, columns=COLS)
        df.to_csv(path, index=False)
    else:
        with path.open("w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=COLS, extrasaction="ignore")
            w.writeheader()
            for r in rows:
                w.writerow({c: r.get(c, "") for c in COLS})
    return rows


def relpath(path: Path) -> Path:
    try:
        return path.resolve().relative_to(ROOT)
    except ValueError:
        return path


def main() -> None:
    log_path = Path(sys.argv[1]) if len(sys.argv) > 1 else LOG
    if not log_path.is_file():
        raise SystemExit(f"missing {log_path} — run vsyn first")
    text = log_path.read_text(encoding="utf-8", errors="replace")
    row = parse_log(text)
    if not row["design"]:
        raise SystemExit(f"no TOP_MOD_NAME in {log_path}")
    out = PART / f"{row['design']}.csv"
    upsert(out, row)
    print(relpath(out).as_posix())


if __name__ == "__main__":
    main()
