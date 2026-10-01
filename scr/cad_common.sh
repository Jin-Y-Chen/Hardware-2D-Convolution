#!/usr/bin/env bash
# Shared by ssh_vlog / ssh_vsim / ssh_vsyn. Source from those scripts.

REMOTE_USER="jinchen"
REMOTE_NAME="CAD"
REMOTE_HOST="lab40.ece.stonybrook.edu"
REMOTE_PROJECT_REL="ese507/project"
REMOTE_RTL_REL="ese507/project/rtl"
REMOTE_TB_REL="ese507/project/tb"
REMOTE_SIM_REL="ese507/project/sim"
REMOTE_SYN_REL="ese507/project/syn"
REMOTE_CONSTRAINT_REL="ese507/project/constraint"
REMOTE_LOG_REL="ese507/project/log"

CAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$CAD_DIR/.." && pwd)"
LOCAL_RTL="$PROJECT_ROOT/rtl"
LOCAL_TB="$PROJECT_ROOT/tb"
LOCAL_SIM="$PROJECT_ROOT/sim"
LOCAL_SYN="$PROJECT_ROOT/syn"
LOCAL_CONSTRAINT="$PROJECT_ROOT/constraint"
LOCAL_LOG="$PROJECT_ROOT/log"

# Git Bash / MSYS has no rsync. Re-run the caller (ssh_link, …) inside WSL.
host_to_wsl_path() {
    local p="${1//\\//}"
    if [[ "$p" =~ ^/([a-zA-Z])/(.*)$ ]]; then
        printf '/mnt/%s/%s' "${BASH_REMATCH[1],,}" "${BASH_REMATCH[2]}"
    elif [[ "$p" =~ ^/cygdrive/([a-zA-Z])/(.*)$ ]]; then
        printf '/mnt/%s/%s' "${BASH_REMATCH[1],,}" "${BASH_REMATCH[2]}"
    elif [[ "$p" =~ ^([A-Za-z]):/(.*)$ ]]; then
        printf '/mnt/%s/%s' "${BASH_REMATCH[1],,}" "${BASH_REMATCH[2]}"
    else
        printf '%s' "$p"
    fi
}

require_rsync() {
    command -v rsync >/dev/null 2>&1 && return 0
    local wsl_bin caller caller_wsl
    wsl_bin=$(command -v wsl.exe 2>/dev/null || command -v wsl || true)
    if [[ -z "$wsl_bin" ]]; then
        echo "rsync not found. Run from WSL, or: sudo apt install rsync" >&2
        exit 1
    fi
    caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    caller="$(cd "$(dirname "$caller")" && pwd)/$(basename "$caller")"
    caller_wsl="$(host_to_wsl_path "$caller")"
    echo "rsync not in PATH (Git Bash). Re-running via WSL." >&2
    exec "$wsl_bin" -e bash "$caller_wsl" "$@"
}

require_rsync "$@"

list_rtl() {
    find "$LOCAL_RTL" \( -name '*.sv' -o -name '*.c' \) ! -name 'params.sv' -print \
        | sed "s|^$LOCAL_RTL/||" | sort
}

list_tb() {
    [[ -d "$LOCAL_TB" ]] || return 0
    find "$LOCAL_TB" \( -name '*.sv' -o -name '*.c' \) ! -name 'params.sv' -print \
        | sed "s|^$LOCAL_TB/||" | sort
}

# DUT RTL that shares mac_tb (basename without .sv)
list_duts() {
    local f rel base
    [[ -d "$LOCAL_RTL" ]] || return 0
    while IFS= read -r f; do
        rel="${f#"$LOCAL_RTL"/}"
        base="${rel##*/}"
        base="${base%.sv}"
        printf '%s  rtl/%s\n' "$base" "$rel"
    done < <(find "$LOCAL_RTL" \( -name 'mac.sv' -o -name 'mac_pipe.sv' \) -print | sort)
}

# Designs recorded by the last successful vlog (log/vlog_files).
designs_from_vlog() {
    local f
    [[ -f "$LOCAL_LOG/vlog_files" ]] || return 0
    while IFS= read -r f; do
        f="${f//$'\r'/}"
        [[ -n "$f" ]] || continue
        case "$f" in
            */mac.sv|mac.sv) echo "mac  $f" ;;
            */mac_pipe.sv|mac_pipe.sv) echo "mac_pipe  $f" ;;
        esac
    done < "$LOCAL_LOG/vlog_files"
}

# Elaboration tops: tb/**/*_tb.sv → module name + path
list_tops() {
    local f rel base
    [[ -d "$LOCAL_TB" ]] || return 0
    while IFS= read -r f; do
        rel="${f#"$LOCAL_TB"/}"
        base="${rel##*/}"
        base="${base%.sv}"
        printf '%s  tb/%s\n' "$base" "$rel"
    done < <(find "$LOCAL_TB" \( -name '*_tb.sv' -o -name '*_tb_mod.sv' \) -print | sort)
}

# Project-relative paths: rtl/part1/mac.sv  tb/part1/mac_tb.sv
list_src() {
    local f
    while IFS= read -r f; do
        [[ -n "$f" ]] && echo "rtl/$f"
    done < <(list_rtl)
    while IFS= read -r f; do
        [[ -n "$f" ]] && echo "tb/$f"
    done < <(list_tb)
}

# Map a user path or short name (mac, mac_pipe, mac_tb) to rtl/<rel> or tb/<rel>.
locate_src() {
    local raw="$1" rel tree=""
    raw="${raw#./}"
    raw="${raw%.sv}"
    if [[ "$raw" != */* ]]; then
        if [[ -f "$LOCAL_RTL/part1/${raw}.sv" ]]; then
            echo "rtl/part1/${raw}.sv"
            return
        fi
        if [[ -f "$LOCAL_TB/part1/${raw}.sv" ]]; then
            echo "tb/part1/${raw}.sv"
            return
        fi
    fi
    raw="$1"
    raw="${raw#./}"
    if [[ "$raw" == rtl/* ]]; then
        tree="rtl"
        rel="${raw#rtl/}"
    elif [[ "$raw" == tb/* ]]; then
        tree="tb"
        rel="${raw#tb/}"
    else
        rel="$raw"
    fi

    if [[ "$tree" == "tb" ]]; then
        [[ -f "$LOCAL_TB/$rel" ]] && echo "tb/$rel"
        return
    fi
    if [[ "$tree" == "rtl" ]]; then
        [[ -f "$LOCAL_RTL/$rel" ]] && echo "rtl/$rel"
        return
    fi
    if [[ -f "$LOCAL_RTL/$rel" ]]; then
        echo "rtl/$rel"
        return
    fi
    if [[ -f "$LOCAL_TB/$rel" ]]; then
        echo "tb/$rel"
        return
    fi
}

normalize_rtl() {
    local p="$1"
    p="${p#./}"
    p="${p#rtl/}"
    echo "$p"
}

# RTL-only list (vsyn). FILE_LIST is relative to rtl/.
resolve_rtl_files() {
    local raw rel has_pkg f
    local -a files=()

    if [[ "${WANT_ALL:-0}" -eq 1 ]]; then
        mapfile -t SELECTED < <(list_rtl)
    fi

    if [[ ${#SELECTED[@]} -eq 0 ]]; then
        echo "Pick at least one file (paths relative to rtl/)." >&2
        echo >&2
        echo "Sources under rtl/:" >&2
        list_rtl >&2
        exit 2
    fi

    for raw in "${SELECTED[@]}"; do
        rel="$(normalize_rtl "$raw")"
        if [[ ! -f "$LOCAL_RTL/$rel" ]]; then
            echo "Not found: rtl/$rel" >&2
            exit 2
        fi
        files+=("$rel")
    done

    if [[ -f "$LOCAL_RTL/comm_pkg.sv" ]]; then
        has_pkg=0
        for f in "${files[@]}"; do
            [[ "$f" == comm_pkg.sv ]] && has_pkg=1
        done
        if [[ "$has_pkg" -eq 0 ]]; then
            files=(comm_pkg.sv "${files[@]}")
        fi
    fi

    FILE_LIST="${files[*]}"
}

# RTL + TB. FILE_LIST is project-relative (rtl/... tb/...).
resolve_src_files() {
    local raw loc has_pkg f
    local -a files=()

    if [[ "${WANT_ALL:-0}" -eq 1 ]]; then
        mapfile -t SELECTED < <(list_src)
    fi

    if [[ ${#SELECTED[@]} -eq 0 ]]; then
        echo "Pick at least one file (paths under rtl/ or tb/)." >&2
        echo >&2
        echo "Sources:" >&2
        list_src >&2
        exit 2
    fi

    for raw in "${SELECTED[@]}"; do
        loc="$(locate_src "$raw")"
        if [[ -z "$loc" ]]; then
            echo "Not found: $raw" >&2
            exit 2
        fi
        files+=("$loc")
    done

    if [[ -f "$LOCAL_RTL/comm_pkg.sv" ]]; then
        has_pkg=0
        for f in "${files[@]}"; do
            [[ "$f" == rtl/comm_pkg.sv ]] && has_pkg=1
        done
        if [[ "$has_pkg" -eq 0 ]]; then
            files=(rtl/comm_pkg.sv "${files[@]}")
        fi
    fi

    FILE_LIST="${files[*]}"
}

# Course TB include of params.sv — written by sim/part1/genParams1 into constraint/param.
ensure_part1_params() {
    local dest="$LOCAL_CONSTRAINT/param/params.sv"
    local gen="$LOCAL_SIM/part1/genParams1"
    [[ "${FILE_LIST:-}" == *mac_tb* || "${FILE_LIST:-}" == *tb/part1* ]] || return 0
    [[ -f "$dest" ]] && return 0
    [[ -f "$gen" ]] || return 0
    (cd "$LOCAL_SIM/part1" && bash ./genParams1 8 24 0)
}

# True if every compile path is comm_pkg or under part1/ (simParams1's unit).
sources_are_part1() {
    local f
    [[ -n "${FILE_LIST:-}" ]] || return 1
    for f in $FILE_LIST; do
        [[ "$f" == rtl/comm_pkg.sv || "$f" == comm_pkg.sv ]] && continue
        [[ "$f" == *part1/* ]] || return 1
    done
    return 0
}

read_part1_params() {
    local dest="$LOCAL_CONSTRAINT/param/params.sv"
    P1_WIDTH=8
    P1_ACCW=24
    P1_PIPE=0
    P1_SEED=random
    [[ -f "$dest" ]] || return 0
    P1_WIDTH=$(sed -n 's/^`define WIDTHVAL //p' "$dest" | tr -d '\r')
    P1_ACCW=$(sed -n 's/^`define ACCWVAL //p' "$dest" | tr -d '\r')
    P1_PIPE=$(sed -n 's/^`define PIPELINEDVAL //p' "$dest" | tr -d '\r')
    P1_SEED=$(sed -n 's/^`define SEEDVAL //p' "$dest" | tr -d '\r')
    [[ -n "$P1_WIDTH" ]] || P1_WIDTH=8
    [[ -n "$P1_ACCW" ]] || P1_ACCW=24
    [[ -n "$P1_PIPE" ]] || P1_PIPE=0
    [[ -n "$P1_SEED" ]] || P1_SEED=random
}

# Same params.sv + file list on vlog / vsim / vsyn consoles.
show_run_context() {
    local dest="$LOCAL_CONSTRAINT/param/params.sv" f
    local -a shown=()
    if [[ -f "$dest" ]]; then
        echo "params  $(grep define "$dest" | tr -s '[:space:]' ' ' | paste -sd' ' - | tr -d '\r')"
    else
        echo "params  (missing constraint/param/params.sv)"
    fi
    for f in ${FILE_LIST:-}; do
        case "$f" in
            rtl/*|tb/*|sim/*|syn/*|constraint/*) shown+=("$f") ;;
            *) shown+=("rtl/$f") ;;
        esac
    done
    echo "files   ${shown[*]}"
}

# Reuse one SSH login for vlog/vsim plus the follow-up rsync (no second password).
SSH_CTL="${HOME}/.ssh/cm-ese507-%C"
mkdir -p "${HOME}/.ssh"

# CAD prints this on every SSH; it is not a transfer error.
filter_lab_noise() {
    grep -v 'cannot find name for group ID' || true
}

ssh_cad() {
    ssh -o ControlMaster=auto \
        -o "ControlPath=${SSH_CTL}" \
        -o ControlPersist=10m \
        "$REMOTE_USER@$REMOTE_HOST" \
        "csh -c 'if (! -f \$HOME/ese507setup-csh) cp /home/home4/pmilder/ese507/ese507setup-csh \$HOME/; source \$HOME/ese507setup-csh; exec /bin/bash -s'" \
        2> >(filter_lab_noise >&2)
}

rsync_from_remote() {
    rsync -az -e "ssh -o ControlMaster=auto -o ControlPath=${SSH_CTL} -o ControlPersist=10m" \
        "$REMOTE_USER@$REMOTE_HOST:$1" "$2" \
        2> >(filter_lab_noise >&2)
}

rsync_to_remote() {
    rsync -az -e "ssh -o ControlMaster=auto -o ControlPath=${SSH_CTL} -o ControlPersist=10m" \
        "$1" "$REMOTE_USER@$REMOTE_HOST:$2" \
        2> >(filter_lab_noise >&2)
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

# Two-way folder under ~/ese507/project/<name>  (rtl, tb, sim, syn, constraint, or log).
rsync_project_ssh() {
    local name="$1"
    shift
    rsync -az --checksum --out-format='%n' \
        -e "ssh -o ControlMaster=auto -o ControlPath=${SSH_CTL} -o ControlPersist=10m" \
        --rsync-path="mkdir -p \$HOME/$REMOTE_PROJECT_REL/$name && rsync" \
        "${RSYNC_TOOL_EXCLUDES[@]}" \
        "$@" \
        2> >(filter_lab_noise >&2)
}

rsync_rtl_ssh() {
    rsync_project_ssh rtl "$@"
}

# Printed into the remote bash script (expand this variable in an unquoted heredoc).
# shellcheck disable=SC2016
REMOTE_CAD_BOOTSTRAP=$(cat <<'BOOT'
set -euo pipefail
set +u
if [ ! -f "$HOME/ese507setup-bash" ] && [ -f /home/home4/pmilder/ese507/ese507setup-bash ]; then
    cp /home/home4/pmilder/ese507/ese507setup-bash "$HOME/"
fi
if [ -f "$HOME/ese507setup-bash" ]; then
    . "$HOME/ese507setup-bash"
fi
export PATH="/usr/local/mgc/questasim/bin:/usr/local/synopsys/syn/U-2022.12-SP7-2/bin:$PATH"
ls /usr/local/mgc /usr/local/mgc/questasim /usr/local/mgc/questasim/bin >/dev/null 2>&1 || true
set -u

VLOG=""
for c in \
    /usr/local/mgc/questasim/bin/vlog \
    /usr/local/mgc/*/questasim/bin/vlog \
    /usr/local/mgc/questa*/bin/vlog
do
    if [ -x "$c" ]; then
        VLOG="$c"
        break
    fi
done
if [ -z "$VLOG" ]; then
    VLOG=$(find /usr/local/mgc /usr/local/mentor /opt/mgc /opt/mentor \
        -name vlog -type f 2>/dev/null | head -n 1 || true)
fi
if [ -n "$VLOG" ] && [ -x "$VLOG" ]; then
    MGC=$(dirname "$VLOG")
    VLIB="$MGC/vlib"
    VSIM="$MGC/vsim"
fi

DC_SHELL=""
for c in \
    /usr/local/synopsys/syn/U-2022.12-SP7-2/bin/dc_shell \
    /usr/local/synopsys/syn/*/bin/dc_shell
do
    if [ -x "$c" ]; then
        DC_SHELL="$c"
        break
    fi
done
if [ -z "$DC_SHELL" ]; then
    DC_SHELL=$(command -v dc_shell 2>/dev/null || true)
fi
BOOT
)
