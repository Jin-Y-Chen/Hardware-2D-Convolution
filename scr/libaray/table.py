#!/usr/bin/env python3
"""Read log/vsyn.log and append one row to data/part1/<top>.csv.

<top> is TOP_MOD_NAME from the log (mac, mac_pipe, …).
The same design, WIDTH, ACCW, and period replaces its old row.
"""

import csv
import re
import sys
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOG = ROOT / "log" / "vsyn.log"
PARAM = ROOT / "rtl" / "param.sv"
OUT_DIR = ROOT / "data" / "part1"

COLS = [
    "design", "width", "accw", "period_ns", "freq_MHz",
    "area_um2", "dyn_uw", "leak_uw", "total_uw",
    "slack_ns", "timing", "path_start", "path_end",
]


def first(pat, text):
    match = re.search(pat, text, re.M)
    return match.group(1).strip() if match else ""


def num(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


# Keep the digits DC printed. mW → uW moves the decimal three places; uW is unchanged.
def as_uw(token, unit):
    token = token.strip()
    if unit != "mW":
        return token
    sign = "-" if token.startswith("-") else ""
    body = token[1:] if sign else token
    whole, _, frac = body.partition(".")
    whole = whole or "0"
    digits = whole + frac
    point = len(whole) + 3
    digits = digits + "0" * max(0, point - len(digits))
    text = digits if point >= len(digits) else digits[:point] + "." + digits[point:]
    text = text.lstrip("0") or "0"
    if text.startswith("."):
        text = "0" + text
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return sign + text


def power_uw(text, pattern):
    match = re.search(pattern, text)
    return as_uw(match.group(1), match.group(2)) if match else ""


# Dynamic plus leakage, both already in uW. Digits are added exactly.
def total_uw(dyn, leak):
    if not dyn or not leak:
        return ""
    text = format(Decimal(dyn) + Decimal(leak), "f")
    return text.rstrip("0").rstrip(".") if "." in text else text


def parse(log_text, param_text):
    design = first(r'set TOP_MOD_NAME\s+"([^"]+)"', log_text)
    # The log no longer echoes WIDTH/ACCW; they live in the package that was compiled.
    width = first(r"localparam int WIDTH = (\d+)", param_text)
    accw = first(r"localparam int ACCW\s+= (\d+)", param_text)
    period = first(r"set CLK_PERIOD\s+([0-9.]+)", log_text)
    area = first(r"Total cell area:\s+([0-9.]+)", log_text)
    dyn = power_uw(log_text, r"Total Dynamic Power\s+=\s+([0-9.]+)\s*(mW|uW)")
    leak = power_uw(log_text, r"Cell Leakage Power\s+=\s+([0-9.]+)\s*(mW|uW)")

    timing_blk = log_text.split("report_timing -loops", 1)[0]
    # "VIOLATED: increase significant digits" is still a violation; slack prints as 0.00.
    slack_m = re.search(r"slack \((MET|VIOLATED)(?::[^)]*)?\)\s+(-?[0-9.]+)", timing_blk)
    period_n = num(period)

    return {
        "design": design,
        "width": width,
        "accw": accw,
        "period_ns": period,
        "freq_MHz": f"{1000.0 / period_n:.6g}" if period_n else "",
        "area_um2": area,
        "dyn_uw": dyn,
        "leak_uw": leak,
        "total_uw": total_uw(dyn, leak),
        "slack_ns": slack_m.group(2) if slack_m else "",
        "timing": slack_m.group(1) if slack_m else "",
        "path_start": first(r"Startpoint:\s+(\S+)", timing_blk),
        "path_end": first(r"Endpoint:\s+(\S+)", timing_blk),
    }


def load_rows(path):
    if not path.is_file() or not path.read_text(encoding="utf-8").strip():
        return []
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    # Older tables stored dynamic power in mW.
    for row in rows:
        if not row.get("dyn_uw") and row.get("dyn_mw"):
            row["dyn_uw"] = as_uw(row["dyn_mw"], "mW")
        if not row.get("timing") and row.get("met") in ("0", "1"):
            row["timing"] = "MET" if row["met"] == "1" else "VIOLATED"
        if not row.get("freq_MHz") and row.get("freq_mhz"):
            row["freq_MHz"] = row["freq_mhz"]
        if not row.get("total_uw"):
            row["total_uw"] = total_uw(row.get("dyn_uw", ""), row.get("leak_uw", ""))
    return rows


def key(row):
    return (row.get("design", ""), row.get("width", ""), row.get("accw", ""), row.get("period_ns", ""))


def upsert(path, row):
    rows = [old for old in load_rows(path) if key(old) != key(row)]
    rows.append(row)
    rows.sort(key=lambda r: (r.get("design", ""), num(r.get("width")) or 0, num(r.get("accw")) or 0, -(num(r.get("period_ns")) or 0)))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLS)
        writer.writeheader()
        writer.writerows({col: row.get(col, "") for col in COLS} for row in rows)
    return rows


def main():
    log_path = Path(sys.argv[1]) if len(sys.argv) > 1 else LOG
    if not log_path.is_file():
        sys.exit(f"No {log_path}. Run vsyn <top> first.")
    param_text = PARAM.read_text(encoding="utf-8") if PARAM.is_file() else ""
    row = parse(log_path.read_text(encoding="utf-8", errors="replace"), param_text)
    if not row["design"]:
        sys.exit(f"No TOP_MOD_NAME in {log_path}. Run vsyn <top> first.")
    out = OUT_DIR / f"{row['design']}.csv"
    rows = upsert(out, row)
    print(f"{out.relative_to(ROOT)}  {row['design']}  {row['period_ns']} ns  {row['timing']}  {len(rows)} rows")


if __name__ == "__main__":
    main()
