#!/usr/bin/env bash
# Shared by ssh_link / ssh_vlog / ssh_vsim / ssh_vsyn.
[[ -n "${ESE507_CAD_COMMON:-}" ]] && return 0
ESE507_CAD_COMMON=1

# Login and paths on lab40. The project lives at ~/ese507/project.
REMOTE_USER="jinchen"
REMOTE_NAME="CAD"
REMOTE_HOST="lab40.ece.stonybrook.edu"
REMOTE_PROJECT_REL="ese507/project"
REMOTE_LOG_REL="ese507/project/log"

# This file is scr/libaray/cad_common.sh; the repo root is two levels up.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
LOCAL_RTL="$PROJECT_ROOT/rtl"
LOCAL_TB="$PROJECT_ROOT/tb"
LOCAL_CONSTRAINT="$PROJECT_ROOT/constraint"
LOCAL_LOG="$PROJECT_ROOT/log"
ALL_CONFIG="$LOCAL_CONSTRAINT/all_config.json"
PARAM_PKG="$LOCAL_RTL/param.sv"

# rsync is required for link and for copying logs back.
require_rsync() {
    command -v rsync >/dev/null 2>&1 && return 0
    echo "rsync not found. sudo apt install rsync" >&2
    exit 1
}

require_rsync "$@"

# Write rtl/param.sv from constraint/all_config.json.
# Sets P_WIDTH P_ACCW P_PIPE CFG_SEED CFG_CLK CFG_RST CFG_PERIOD
#     P_R P_C P_K P_TVPR P_STAGE P_TRPR.
# Part 2 names match genParams2: WIDTH R C K TVALID_PROB STAGE.
apply_config() {
    local line
    line=$(python3 - "$ALL_CONFIG" "$PARAM_PKG" <<'PY'
import json, pathlib, sys

cfg_path, pkg_path = map(pathlib.Path, sys.argv[1:3])

def as_int(section, key):
    val = cfg[section][key]
    # bool is a subclass of int; reject it so JSON true cannot become 1.
    if isinstance(val, bool) or not isinstance(val, int):
        raise ValueError(key)
    return val

def fmt_prob(val):
    if isinstance(val, bool) or not isinstance(val, (int, float)):
        raise ValueError("TVALID_PROB")
    if isinstance(val, float) and not val.is_integer():
        text = format(val, "f").rstrip("0").rstrip(".")
        if text.startswith("."):
            text = "0" + text
        return text
    return str(int(val))

try:
    cfg = json.loads(cfg_path.read_text())
    width = int(cfg["design"]["WIDTH"])
    accw = int(cfg["design"]["ACCW"])
    pipelined = int(cfg["design"]["PIPELINED"])
    rows = as_int("design", "R")
    cols = as_int("design", "C")
    k = as_int("design", "K")
    stage = as_int("sim", "STAGE")
    tvpr = fmt_prob(cfg["sim"]["TVALID_PROB"])
    trpr = fmt_prob(cfg["sim"]["TREADY_PROB"])
    seed = str(cfg["sim"]["seed"])
    clk = str(cfg["syn"]["clk"])
    rst = str(cfg["syn"]["rst"])
    period = cfg["syn"]["period_ns"]
except Exception:
    sys.exit(
        "Edit constraint/all_config.json: "
        "design.WIDTH, design.ACCW, design.PIPELINED, "
        "design.R, design.C, design.K, "
        "sim.TVALID_PROB, sim.TREADY_PROB, sim.STAGE, sim.seed, "
        "syn.clk, syn.rst, syn.period_ns."
    )

pkg_path.write_text(
    "// Generated from constraint/all_config.json. Edit that file, not this one.\n"
    "package param;\n"
    f"    localparam int WIDTH = {width};  // input / output bits\n"
    f"    localparam int ACCW  = {accw};  // accumulator bits\n"
    f"    localparam int PIPELINED = {pipelined};  // testbench: 0 = mac, 1 = mac_pipe\n"
    "\n"
    f"    localparam int R = {rows};  // rows in X\n"
    f"    localparam int C = {cols};  // cols in X\n"
    f"    localparam int K = {k};  // rows and cols in W\n"
    "\n"
    "    localparam signed [ACCW-1:0] MAXOUT = (1 <<< (WIDTH-1)) - 1;\n"
    "    localparam signed [ACCW-1:0] MINOUT = -(1 <<< (WIDTH-1));\n"
    "endpackage\n"
)
print(width, accw, pipelined, seed, clk, rst, period, rows, cols, k, tvpr, stage, trpr)
PY
    ) || exit 2
    # shellcheck disable=SC2086
    read -r P_WIDTH P_ACCW P_PIPE CFG_SEED CFG_CLK CFG_RST CFG_PERIOD \
        P_R P_C P_K P_TVPR P_STAGE P_TRPR <<< "$line"
}

# Same limits the input_mems testbench enforces at time zero.
check_input_mems() {
    python3 - "$P_WIDTH" "$P_R" "$P_C" "$P_K" "$P_TVPR" "$P_STAGE" <<'PY'
import sys
width, rows, cols, k, stage = (int(float(sys.argv[i])) for i in (1, 2, 3, 4, 6))
tvpr = float(sys.argv[5])
problems = []
if not 2 <= width < 32:
    problems.append("design.WIDTH must be 2 <= WIDTH < 32")
if rows < 3 or cols < 3:
    problems.append("design.R and design.C must both be >= 3")
if k < 2:
    problems.append("design.K must be >= 2")
if k >= rows or k >= cols:
    problems.append("design.K must be < design.R and design.C")
if stage not in (1, 2, 3):
    problems.append("sim.STAGE must be 1, 2, or 3")
if tvpr != 0 and not 0.001 <= tvpr <= 1:
    problems.append("sim.TVALID_PROB must be 0 (random) or from 0.001 to 1")
if problems:
    sys.exit("Edit constraint/all_config.json: " + "; ".join(problems) + ".")
PY
}

# Limits Conv_tb checks at time zero. ACCW is derived from WIDTH and K.
check_conv() {
    python3 - "$P_WIDTH" "$P_R" "$P_C" "$P_K" "$P_TVPR" "$P_TRPR" <<'PY'
import math, sys
width, rows, cols, k = (int(float(sys.argv[i])) for i in (1, 2, 3, 4))
tvpr, trpr = float(sys.argv[5]), float(sys.argv[6])
problems = []
if not 2 <= width < 32:
    problems.append("design.WIDTH must be 2 <= WIDTH < 32")
if rows < 3 or cols < 3:
    problems.append("design.R and design.C must both be >= 3")
if k < 2:
    problems.append("design.K must be >= 2")
if k >= rows or k >= cols:
    problems.append("design.K must be < design.R and design.C")
span = k * k * (1 << (2 * width - 2)) + (1 << (width - 1))
accw = (math.ceil(math.log2(span)) if span > 1 else 0) + 1
if accw > 80:
    problems.append("ACCW derived from design.WIDTH and design.K must be <= 80")
for name, val in (("sim.TVALID_PROB", tvpr), ("sim.TREADY_PROB", trpr)):
    if val != 0 and not 0.001 <= val <= 1:
        problems.append(name + " must be 0 (random) or from 0.001 to 1")
if problems:
    sys.exit("Edit constraint/all_config.json: " + "; ".join(problems) + ".")
PY
}

# One SSH session for the whole command. Later rsync calls reuse it (ControlPersist 10m).
SSH_CTL="${HOME}/.ssh/cm-ese507-%C"
mkdir -p "${HOME}/.ssh"
RSYNC_RSH="ssh -o ControlMaster=auto -o ControlPath=${SSH_CTL} -o ControlPersist=10m"

# Drop the CAD login line that is not a transfer error.
filter_lab_noise() { grep -v 'cannot find name for group ID' || true; }

# Run one scr/libaray/remote.py command on CAD after the course setup.
# The script is piped to /tmp/ese507-remote.py; $@ becomes its arguments.
remote_py() {
    local quoted="" a
    for a in "$@"; do
        quoted+=" \"${a//\"/}\""
    done
    ssh -o ControlMaster=auto -o "ControlPath=${SSH_CTL}" -o ControlPersist=10m \
        "$REMOTE_USER@$REMOTE_HOST" \
        "csh -c 'if (! -f \$HOME/ese507setup-csh) cp /home/home4/pmilder/ese507/ese507setup-csh \$HOME/; source \$HOME/ese507setup-csh; cat > /tmp/ese507-remote.py; exec python3 /tmp/ese507-remote.py$quoted'" \
        < "$LIB_DIR/remote.py" \
        2> >(filter_lab_noise >&2)
}

# Create project directories on CAD.
remote_dirs() { remote_py dirs --proj "$REMOTE_PROJECT_REL" "$@"; }
# Remove leftover params.sv copies on CAD.
remote_tidy() { remote_py tidy --proj "$REMOTE_PROJECT_REL"; }

# Copy one file from CAD to this computer.
rsync_from_remote() {
    rsync -az -e "$RSYNC_RSH" "$REMOTE_USER@$REMOTE_HOST:$1" "$2" 2> >(filter_lab_noise >&2)
}
# Copy one file from this computer to CAD.
rsync_to_remote() {
    rsync -az -e "$RSYNC_RSH" "$1" "$REMOTE_USER@$REMOTE_HOST:$2" 2> >(filter_lab_noise >&2)
}

# Generated CAD files — never copy these to or from the host.
RSYNC_TOOL_EXCLUDES=(
    --exclude 'work/'
    --exclude 'work_synth/'
    --exclude '*.wlf'
    --exclude 'transcript'
    --exclude 'modelsim.ini'
    --exclude 'vsim.dbg'
    --exclude 'vlog_mac.log'
    --exclude 'vsim_mac.log'
    --exclude 'dc_mac.log'
    --exclude 'command.log'
    --exclude 'default.svf'
    --exclude '*.svf'
    --exclude 'user.tcl'
    --exclude '*.vstf'
    --exclude 'wlft*'
    --exclude '_info'
    --exclude '_vmake'
    --exclude '_lib*'
    --exclude '.nfs*'
    --exclude '*.do'
)

# Sync one project folder (rtl, tb, or log) with CAD. sim/ and syn/ stay on CAD.
rsync_project_ssh() {
    local name="$1"
    shift
    rsync -az --checksum --out-format='%n' -e "$RSYNC_RSH" \
        --rsync-path="mkdir -p \$HOME/$REMOTE_PROJECT_REL/$name && rsync" \
        "${RSYNC_TOOL_EXCLUDES[@]}" \
        "$@" \
        2> >(filter_lab_noise >&2)
}

# Map a short name or path (mac, mac_tb, rtl/part1/mac.sv) to a project-relative path.
locate_src() {
    local raw="${1#./}" base="${1#./}"
    base="${base%.sv}"
    base="${base%.c}"
    if [[ "$base" != */* ]]; then
        if [[ -f "$LOCAL_RTL/part1/${base}.sv" ]]; then echo "rtl/part1/${base}.sv"; return; fi
        if [[ -f "$LOCAL_RTL/part2/${base}.sv" ]]; then echo "rtl/part2/${base}.sv"; return; fi
        if [[ -f "$LOCAL_RTL/part3/${base}.sv" ]]; then echo "rtl/part3/${base}.sv"; return; fi
        if [[ -f "$LOCAL_TB/part1/${base}.sv" ]]; then echo "tb/part1/${base}.sv"; return; fi
        if [[ -f "$LOCAL_TB/part2/${base}.sv" ]]; then echo "tb/part2/${base}.sv"; return; fi
        if [[ -f "$LOCAL_TB/part3/${base}.sv" ]]; then echo "tb/part3/${base}.sv"; return; fi
        if [[ -f "$LOCAL_TB/part4/${base}.sv" ]]; then echo "tb/part4/${base}.sv"; return; fi
        if [[ -f "$LOCAL_TB/part1/${base}.c" ]]; then echo "tb/part1/${base}.c"; return; fi
        if [[ -f "$LOCAL_TB/part3/${base}.c" ]]; then echo "tb/part3/${base}.c"; return; fi
        if [[ -f "$LOCAL_TB/part4/${base}.c" ]]; then echo "tb/part4/${base}.c"; return; fi
    fi
    [[ -f "$PROJECT_ROOT/$raw" ]] && { echo "$raw"; return; }
    echo "Not found: $1. Pass [DUT] or [TOP], or a path under rtl/ or tb/." >&2
    return 1
}

# Write params.sv on CAD for part 2 and part 3. Both testbenches `include "params.sv".
# The host does not keep a sim/ folder for this.
write_remote_params() {
    remote_py params --proj "$REMOTE_PROJECT_REL" \
        --width "$P_WIDTH" --rows "$P_R" --cols "$P_C" --k "$P_K" \
        --tvpr "$P_TVPR" --trpr "$P_TRPR" --stage "$P_STAGE"
}

# Conv needs the rest of rtl/part3, not only Conv.sv.
add_src() {
    local f
    for f in "${files[@]}"; do
        [[ "$f" == "$1" ]] && return 0
    done
    files+=("$1")
}

# Compile on CAD. Does not sync the project tree (that is link).
# Uploads the generated rtl/param.sv and writes params.sv on CAD.
# Conv also compiles rtl/part3/input_mems.sv, mac_pipe.sv, and fifo_out.sv.
# Other sources must already be on CAD.
cad_vlog() {
    apply_config
    local -a files=(rtl/param.sv)
    local f loc
    for f in "$@"; do
        [[ "$f" == rtl/param.sv ]] && continue
        loc="$(locate_src "$f")"
        if [[ "$loc" == rtl/part3/Conv.sv ]]; then
            add_src rtl/part3/input_mems.sv
            add_src rtl/part3/mac_pipe.sv
            add_src rtl/part3/fifo_out.sv
            add_src rtl/part3/Conv.sv
        else
            add_src "$loc"
        fi
    done
    FILE_LIST="${files[*]}"   # vsyn reads this when it writes SRC_FILE on CAD
    remote_dirs rtl
    rsync_to_remote "$PARAM_PKG" "~/$REMOTE_PROJECT_REL/rtl/param.sv"
    write_remote_params
    echo "vlog  ${FILE_LIST}"
    set +e
    remote_py vlog --proj "$REMOTE_PROJECT_REL" "${files[@]}"
    local rc=$?
    set -e
    mkdir -p "$LOCAL_LOG"
    rsync_from_remote "~/$REMOTE_LOG_REL/vlog.log" "$LOCAL_LOG/vlog.log" || true
    return "$rc"
}
