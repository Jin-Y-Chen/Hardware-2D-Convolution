#!/usr/bin/env python3
"""Scatter one CSV column against another.

pplot <file> <x-axis> <y-axis> [MET]
pplot [mac, mac_pipe] freq_MHz area_um2 MET
MET keeps only rows whose timing is MET.
One file writes data/part1/<file>_<x>_<y>.svg.
Several files share one graph.
"""

import csv
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PART = ROOT / "data" / "part1"

PANEL_W = 480
PANEL_H = 360
PAD_L, PAD_R, PAD_T, PAD_B = 72, 20, 16, 52


def num(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def csv_path(name):
    path = Path(name)
    if not path.is_file():
        path = PART / (name if name.endswith(".csv") else f"{name}.csv")
    if not path.is_file():
        sys.exit(f"No {path}. Run pdata first.")
    return path


def load(path):
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        sys.exit(f"{path} has no rows.")
    return rows


def pairs(rows, x_key, y_key, timing):
    points = []
    for row in rows:
        if timing and row.get("timing") != timing:
            continue
        x = num(row.get(x_key))
        y = num(row.get(y_key))
        if x is not None and y is not None:
            points.append((x, y))
    return points


# Equal steps of 1, 2, or 5 times a power of ten, so every tick is a whole number.
def step_size(span, count=5):
    raw = span / count
    if raw <= 0:
        return 1
    exp = math.floor(math.log10(raw))
    frac = raw / 10 ** exp
    nice = 1 if frac <= 1 else 2 if frac <= 2 else 5 if frac <= 5 else 10
    return nice * 10 ** exp


def scale(values):
    lo = min(0.0, min(values))
    hi = max(values)
    if hi == lo:
        hi = lo + 1
    step = step_size(hi - lo)
    lo = math.floor(lo / step) * step
    hi = math.ceil(max(values) / step) * step
    if hi <= lo:
        hi = lo + step
    # Twice as many ticks: a mark at the halfway point of each step.
    step /= 2
    count = int(round((hi - lo) / step))
    ticks = [lo + step * i for i in range(count + 1)]
    return lo, hi, ticks


def tick_label(value):
    rounded = round(value)
    return str(int(rounded)) if abs(value - rounded) < 1e-6 else f"{value:.6g}"


def esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# mhz would read as millihertz. The column and the axis use MHz.
AXIS = {"freq_mhz": "freq_MHz", "freq_Mhz": "freq_MHz", "freq_mHz": "freq_MHz"}
LABEL = {"freq_MHz": "Frequency (MHz)", "total_uw": "Total power (µW)"}
COLORS = ("#1f4e79", "#c45911", "#548235", "#7030a0")
USAGE = "pplot <file> <x-axis> <y-axis> [MET]\npplot [mac, mac_pipe] freq_MHz area_um2 MET"


def mark(shape, x, y, color):
    if shape == "square":
        return f'<rect x="{x - 3.5:.2f}" y="{y - 3.5:.2f}" width="7" height="7" fill="{color}"/>'
    return f'<circle cx="{x:.2f}" cy="{y:.2f}" r="4" fill="{color}"/>'


def draw(series, x_key, y_key, timing):
    xs = [x for _, points in series for x, _ in points]
    ys = [y for _, points in series for _, y in points]
    x0, x1, x_ticks = scale(xs)
    y0, y1, y_ticks = scale(ys)
    legend_h = 16 * len(series) if len(series) > 1 else 0
    left, top = PAD_L, PAD_T + legend_h
    width = PANEL_W - PAD_L - PAD_R
    height = PANEL_H - PAD_T - PAD_B

    def sx(x):
        return left + (x - x0) / (x1 - x0) * width

    def sy(y):
        return top + (y1 - y) / (y1 - y0) * height

    lines = [
        f'<rect x="{left}" y="{top}" width="{width}" height="{height}" fill="white" stroke="#222"/>',
    ]
    for value in x_ticks:
        px = sx(value)
        if abs(value - x0) > 1e-6 and abs(value - x1) > 1e-6:
            lines.append(f'<line x1="{px:.2f}" y1="{top}" x2="{px:.2f}" y2="{top + height}" stroke="#ccc"/>')
        lines.append(f'<line x1="{px:.2f}" y1="{top + height}" x2="{px:.2f}" y2="{top + height + 4}" stroke="#222"/>')
        lines.append(f'<text x="{px:.2f}" y="{top + height + 18}" text-anchor="middle" font-size="11">{tick_label(value)}</text>')
    for value in y_ticks:
        py = sy(value)
        if abs(value - y0) > 1e-6 and abs(value - y1) > 1e-6:
            lines.append(f'<line x1="{left}" y1="{py:.2f}" x2="{left + width}" y2="{py:.2f}" stroke="#ccc"/>')
        lines.append(f'<line x1="{left - 4}" y1="{py:.2f}" x2="{left}" y2="{py:.2f}" stroke="#222"/>')
        lines.append(f'<text x="{left - 8}" y="{py + 4:.2f}" text-anchor="end" font-size="11">{tick_label(value)}</text>')
    lines.append(f'<text x="{left + width / 2}" y="{PANEL_H + legend_h - 8}" text-anchor="middle" font-size="12">{esc(LABEL.get(x_key, x_key))}</text>')
    lines.append(
        f'<text transform="translate(16 {top + height / 2}) rotate(-90)" text-anchor="middle" font-size="12">{esc(LABEL.get(y_key, y_key))}</text>'
    )
    for index, (name, points) in enumerate(series):
        color = COLORS[index % len(COLORS)]
        shape = "square" if index else "circle"
        for x, y in points:
            lines.append(mark(shape, sx(x), sy(y), color))
        if len(series) > 1:
            ly = PAD_T + 4 + index * 16
            lines.append(mark(shape, left + 6, ly - 4, color))
            lines.append(f'<text x="{left + 16}" y="{ly}" font-size="12">{esc(name)}</text>')
    names = "_".join(name for name, _ in series)
    suffix = f"_{timing}" if timing else ""
    out = PART / f"{names}_{x_key}_{y_key}{suffix}.svg"
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{PANEL_W}" height="{PANEL_H + legend_h}" '
        f'font-family="sans-serif">\n' + "\n".join(lines) + "\n</svg>\n"
    )
    out.write_text(svg, encoding="utf-8")
    return out


def file_names(tokens):
    blob = " ".join(tokens).strip()
    if blob.startswith("[") and blob.endswith("]"):
        blob = blob[1:-1]
    names = [part.strip("[].,") for part in blob.replace(",", " ").split()]
    return [name for name in names if name]


def main():
    args = sys.argv[1:]
    timing = ""
    if args and args[-1].upper() == "MET":
        timing = "MET"
        args = args[:-1]
    if len(args) < 3:
        sys.exit(USAGE)
    x_key, y_key = AXIS.get(args[-2], args[-2]), AXIS.get(args[-1], args[-1])
    names = file_names(args[:-2])
    if not names:
        sys.exit(USAGE)
    series = []
    which = "MET rows" if timing else "rows"
    for name in names:
        path = csv_path(name)
        rows = load(path)
        missing = [col for col in (x_key, y_key) if col not in rows[0]]
        if missing:
            sys.exit(f"No column {', '.join(missing)} in {path.name}. Columns: {', '.join(rows[0])}")
        points = pairs(rows, x_key, y_key, timing)
        if not points:
            sys.exit(f"No {which} with numbers in {x_key} and {y_key} in {path.name}.")
        series.append((path.stem, points))
    out = draw(series, x_key, y_key, timing)
    print(out.relative_to(ROOT))


if __name__ == "__main__":
    main()
