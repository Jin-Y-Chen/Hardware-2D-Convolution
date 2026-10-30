#!/usr/bin/env python3
"""Scatter one CSV column against another.

pplot <file> <x-axis> <y-axis> [MET]
pplot [mac, mac_pipe] freq_MHz area_um2 MET
pplot mac_pipe freq_MHz 'total_uw*period_ns' MET
MET keeps only rows whose timing is MET.
Quote a product so the shell does not expand *: 'total_uw*period_ns'
or '[total_uw * period_ns]'.
One file writes data/partN/<file>_<x>_<y>.pdf next to that CSV.
Several files share one graph.
"""

import ast
import csv
import math
import operator
import re
import sys
from pathlib import Path

try:
    from reportlab.lib.colors import HexColor, black, white
    from reportlab.pdfgen import canvas
except ImportError:
    sys.exit("pplot needs reportlab. Install it with:  python3 -m pip install --user reportlab")

ROOT = Path(__file__).resolve().parents[2]
PARTS = [ROOT / "data" / name for name in ("part1", "part2", "part3")]

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
    if path.is_file():
        return path
    filename = name if name.endswith(".csv") else f"{name}.csv"
    for part in PARTS:
        candidate = part / filename
        if candidate.is_file():
            return candidate
    sys.exit(f"No {PARTS[-1] / filename}. Run pdata first.")


def load(path):
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        sys.exit(f"{path} has no rows.")
    return rows


_OPS = {ast.Mult: operator.mul, ast.Add: operator.add, ast.Sub: operator.sub, ast.Div: operator.truediv}


def axis_name(token):
    text = token.strip()
    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1].strip()
    text = re.sub(r"\s+", "", text)
    return AXIS.get(text, text)


def axis_file(key):
    return re.sub(r"[^A-Za-z0-9]+", "_", key).strip("_")


def eval_axis(row, expr):
    if expr in row:
        return num(row.get(expr))
    try:
        tree = ast.parse(expr, mode="eval")
    except SyntaxError:
        return None

    def walk(node):
        if isinstance(node, ast.Expression):
            return walk(node.body)
        if isinstance(node, ast.Name):
            return num(row.get(node.id))
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return float(node.value)
        if isinstance(node, ast.BinOp) and type(node.op) in _OPS:
            left, right = walk(node.left), walk(node.right)
            if left is None or right is None:
                return None
            return _OPS[type(node.op)](left, right)
        raise ValueError("unsupported axis")

    try:
        return walk(tree)
    except (ValueError, TypeError, ZeroDivisionError, KeyError):
        return None


def pairs(rows, x_key, y_key, timing):
    points = []
    for row in rows:
        if timing and row.get("timing") != timing:
            continue
        x = eval_axis(row, x_key)
        y = eval_axis(row, y_key)
        if x is not None and y is not None:
            points.append((x, y))
    return points


def axis_cols(expr):
    if expr in ("design", "timing", "path_start", "path_end"):
        return [expr]
    try:
        tree = ast.parse(expr, mode="eval")
    except SyntaxError:
        return [expr]
    return [node.id for node in ast.walk(tree) if isinstance(node, ast.Name)]


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


# mhz would read as millihertz. The column and the axis use MHz.
# Units are ASCII letters: uW, um2, ns. No µ.
AXIS = {"freq_mhz": "freq_MHz", "freq_Mhz": "freq_MHz", "freq_mHz": "freq_MHz"}
LABEL = {
    "period_ns": "Period (ns)",
    "freq_MHz": "Frequency (MHz)",
    "area_um2": "Area (um2)",
    "dyn_uw": "Dynamic power (uW)",
    "leak_uw": "Leakage power (uW)",
    "total_uw": "Total power (uW)",
    "slack_ns": "Slack (ns)",
    "total_uw*period_ns": "P t (uW ns)",
}
COLORS = ("#1f4e79", "#c45911", "#548235", "#7030a0")
USAGE = (
    "pplot <file> <x-axis> <y-axis> [MET]\n"
    "pplot [mac, mac_pipe] freq_MHz area_um2 MET\n"
    "pplot mac_pipe freq_MHz 'total_uw*period_ns' MET"
)


def mark(pdf, shape, x, y, color, page_h):
    pdf.setFillColor(HexColor(color))
    if shape == "square":
        pdf.rect(x - 3.5, page_h - (y + 3.5), 7, 7, stroke=0, fill=1)
    else:
        pdf.circle(x, page_h - y, 4, stroke=0, fill=1)


def draw(series, x_key, y_key, timing, out_dir):
    xs = [x for _, points in series for x, _ in points]
    ys = [y for _, points in series for _, y in points]
    x0, x1, x_ticks = scale(xs)
    y0, y1, y_ticks = scale(ys)
    legend_h = 16 * len(series) if len(series) > 1 else 0
    page_h = PANEL_H + legend_h
    left, top = PAD_L, PAD_T + legend_h
    width = PANEL_W - PAD_L - PAD_R
    height = PANEL_H - PAD_T - PAD_B

    def sx(x):
        return left + (x - x0) / (x1 - x0) * width

    def sy(y):
        return top + (y1 - y) / (y1 - y0) * height

    names = "_".join(name for name, _ in series)
    suffix = f"_{timing}" if timing else ""
    out = out_dir / f"{names}_{axis_file(x_key)}_{axis_file(y_key)}{suffix}.pdf"
    pdf = canvas.Canvas(str(out), pagesize=(PANEL_W, page_h))

    pdf.setStrokeColor(HexColor("#222222"))
    pdf.setFillColor(white)
    pdf.rect(left, page_h - (top + height), width, height, stroke=1, fill=1)

    pdf.setFont("Helvetica", 11)
    for value in x_ticks:
        px = sx(value)
        if abs(value - x0) > 1e-6 and abs(value - x1) > 1e-6:
            pdf.setStrokeColor(HexColor("#cccccc"))
            pdf.line(px, page_h - top, px, page_h - (top + height))
        pdf.setStrokeColor(HexColor("#222222"))
        pdf.line(px, page_h - (top + height), px, page_h - (top + height + 4))
        pdf.setFillColor(black)
        pdf.drawCentredString(px, page_h - (top + height + 18), tick_label(value))
    for value in y_ticks:
        py = sy(value)
        if abs(value - y0) > 1e-6 and abs(value - y1) > 1e-6:
            pdf.setStrokeColor(HexColor("#cccccc"))
            pdf.line(left, page_h - py, left + width, page_h - py)
        pdf.setStrokeColor(HexColor("#222222"))
        pdf.line(left - 4, page_h - py, left, page_h - py)
        pdf.setFillColor(black)
        pdf.drawRightString(left - 8, page_h - (py + 4), tick_label(value))

    pdf.setFillColor(black)
    pdf.setFont("Helvetica", 12)
    pdf.drawCentredString(left + width / 2, page_h - (PANEL_H + legend_h - 8), LABEL.get(x_key, x_key.replace("_", " ")))
    pdf.saveState()
    pdf.translate(16, page_h - (top + height / 2))
    pdf.rotate(90)
    pdf.drawCentredString(0, 0, LABEL.get(y_key, y_key.replace("_", " ")))
    pdf.restoreState()

    for index, (name, points) in enumerate(series):
        color = COLORS[index % len(COLORS)]
        shape = "square" if index else "circle"
        for x, y in points:
            mark(pdf, shape, sx(x), sy(y), color, page_h)
        if len(series) > 1:
            ly = PAD_T + 4 + index * 16
            mark(pdf, shape, left + 6, ly - 4, color, page_h)
            pdf.setFillColor(black)
            pdf.setFont("Helvetica", 12)
            pdf.drawString(left + 16, page_h - ly, name.replace("_", "-"))
    pdf.save()
    return out


def file_names(tokens):
    blob = " ".join(tokens).strip()
    if blob.startswith("[") and blob.endswith("]") and "," in blob:
        blob = blob[1:-1]
    names = [part.strip("[].,") for part in blob.replace(",", " ").split()]
    return [name for name in names if name]


def recover_globbed_expr(args):
    # [total_uw * period_ns] is split by the shell; * may expand to files.
    start = next(
        (i for i, token in enumerate(args) if token.startswith("[") and "," not in token and not token.endswith("]")),
        None,
    )
    if start is None:
        return args
    end = next(
        (i for i, token in enumerate(args) if i > start and token.endswith("]") and "," not in token),
        None,
    )
    if end is None:
        return args
    left = args[start].lstrip("[").strip()
    right = args[end].rstrip("]").strip()
    mid = []
    for token in args[start + 1 : end]:
        if token in ("*", "+", "-", "/"):
            mid.append(token)
        elif re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token) and not Path(token).exists():
            mid.append(token)
    if not mid:
        mid = ["*"]
    return args[:start] + ["[" + " ".join([left, *mid, right]) + "]"] + args[end + 1 :]


def join_brackets(args):
    joined = []
    i = 0
    while i < len(args):
        token = args[i]
        if token.startswith("[") and not token.endswith("]"):
            chunk = [token]
            i += 1
            while i < len(args) and not args[i].endswith("]"):
                chunk.append(args[i])
                i += 1
            if i < len(args):
                chunk.append(args[i])
                i += 1
            joined.append(" ".join(chunk))
        else:
            joined.append(token)
            i += 1
    return joined


def main():
    args = join_brackets(recover_globbed_expr(sys.argv[1:]))
    timing = ""
    if args and args[-1].upper() == "MET":
        timing = "MET"
        args = args[:-1]
    if len(args) < 3:
        sys.exit(USAGE)
    x_key, y_key = axis_name(args[-2]), axis_name(args[-1])
    names = file_names(args[:-2])
    if not names:
        sys.exit(USAGE)
    series = []
    which = "MET rows" if timing else "rows"
    for name in names:
        path = csv_path(name)
        rows = load(path)
        missing = [col for col in axis_cols(x_key) + axis_cols(y_key) if col not in rows[0]]
        if missing:
            sys.exit(f"No column {', '.join(missing)} in {path.name}. Columns: {', '.join(rows[0])}")
        points = pairs(rows, x_key, y_key, timing)
        if not points:
            sys.exit(f"No {which} with numbers in {x_key} and {y_key} in {path.name}.")
        series.append((path.stem, points))
    out = draw(series, x_key, y_key, timing, csv_path(names[0]).parent)
    print(out.relative_to(ROOT))


if __name__ == "__main__":
    main()
