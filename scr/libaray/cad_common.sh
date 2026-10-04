#!/usr/bin/env bash
# Shared by ssh_link / ssh_vlog / ssh_vsim / ssh_vsyn.
[[ -n "${ESE507_CAD_COMMON:-}" ]] && return 0
ESE507_CAD_COMMON=1

# Login and paths on lab40. The project lives at ~/ese507/project.
REMOTE_USER="jinchen"
REMOTE_NAME="CAD"
REMOTE_HOST="lab40.ece.stonybrook.edu"
REMOTE_PROJECT_REL="ese507/project"
REMOTE_SYN_REL="ese507/project/syn"
REMOTE_LOG_REL="ese507/project/log"

# This file is scr/libaray/cad_common.sh; the repo root is two levels up.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
LOCAL_RTL="$PROJECT_ROOT/rtl"
LOCAL_TB="$PROJECT_ROOT/tb"
LOCAL_SYN="$PROJECT_ROOT/syn"
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
# Sets P_WIDTH P_ACCW P_PIPE CFG_SEED CFG_CLK CFG_RST CFG_PERIOD.
apply_config() {
    local line
    line=$(python3 - "$ALL_CONFIG" "$PARAM_PKG" <<'PY'
import json, pathlib, sys

cfg_path, pkg_path = map(pathlib.Path, sys.argv[1:3])
try:
    cfg = json.loads(cfg_path.read_text())
    width = int(cfg["design"]["WIDTH"])
    accw = int(cfg["design"]["ACCW"])
    pipelined = int(cfg["design"]["PIPELINED"])
    seed = str(cfg["sim"]["seed"])
    clk = str(cfg["syn"]["clk"])
    rst = str(cfg["syn"]["rst"])
    period = cfg["syn"]["period_ns"]
except Exception:
    sys.exit(
        "Edit constraint/all_config.json: "
        "design.WIDTH, design.ACCW, design.PIPELINED, sim.seed, "
        "syn.clk, syn.rst, syn.period_ns."
    )

pkg_path.write_text(
    "// Generated from constraint/all_config.json. Edit that file, not this one.\n"
    "package param;\n"
    f"    localparam int WIDTH = {width};  // input / output bits\n"
    f"    localparam int ACCW  = {accw};  // accumulator bits\n"
    f"    localparam int PIPELINED = {pipelined};  // testbench: 0 = mac, 1 = mac_pipe\n"
    "\n"
    "    localparam signed [ACCW-1:0] MAXOUT = (1 <<< (WIDTH-1)) - 1;\n"
    "    localparam signed [ACCW-1:0] MINOUT = -(1 <<< (WIDTH-1));\n"
    "endpackage\n"
)
print(width, accw, pipelined, seed, clk, rst, period)
PY
    ) || exit 2
    # shellcheck disable=SC2086
    read -r P_WIDTH P_ACCW P_PIPE CFG_SEED CFG_CLK CFG_RST CFG_PERIOD <<< "$line"
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
)

# Sync one project folder (rtl, tb, sim, syn, constraint, or log) with CAD.
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
        if [[ -f "$LOCAL_TB/part1/${base}.sv" ]]; then echo "tb/part1/${base}.sv"; return; fi
        if [[ -f "$LOCAL_TB/part1/${base}.c" ]]; then echo "tb/part1/${base}.c"; return; fi
    fi
    [[ -f "$PROJECT_ROOT/$raw" ]] && { echo "$raw"; return; }
    echo "Not found: $1. Use mac, mac_tb, or a path such as rtl/part1/mac.sv." >&2
    return 1
}

# Compile on CAD. Does not sync the project tree (that is link).
# Uploads only the generated rtl/param.sv. Other sources must already be on CAD.
cad_vlog() {
    apply_config
    local -a files=(rtl/param.sv)
    local f loc
    for f in "$@"; do
        [[ "$f" == rtl/param.sv ]] && continue
        loc="$(locate_src "$f")"
        files+=("$loc")
    done
    FILE_LIST="${files[*]}"   # vsyn reads this when it writes SRC_FILE
    remote_dirs rtl
    rsync_to_remote "$PARAM_PKG" "~/$REMOTE_PROJECT_REL/rtl/param.sv"
    echo "vlog  ${FILE_LIST}"
    set +e
    remote_py vlog --proj "$REMOTE_PROJECT_REL" "${files[@]}"
    local rc=$?
    set -e
    mkdir -p "$LOCAL_LOG"
    rsync_from_remote "~/$REMOTE_LOG_REL/vlog.log" "$LOCAL_LOG/vlog.log" || true
    return "$rc"
}
