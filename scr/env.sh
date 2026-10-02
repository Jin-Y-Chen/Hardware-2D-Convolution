#!/usr/bin/env bash
# WSL / Linux / Git Bash:
#   source scr/env.sh
# Then:  link   vlog   vsim   vsyn   plot
#
# Functions (not aliases) so they override /usr/bin/link and other PATH tools.
# Always launch with bash so missing +x and CRLF shebangs still work.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "source this file:  source scr/env.sh" >&2
    exit 1
fi

unalias link vlog vsim vsyn plot 2>/dev/null || true

_ESE507_SCR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_ese507_scr() {
    local cmd="$1"
    shift
    bash "$_ESE507_SCR/$cmd" "$@"
}

link() { _ese507_scr ssh_link "$@"; }
vlog() { _ese507_scr ssh_vlog "$@"; }
vsim() { _ese507_scr ssh_vsim "$@"; }
vsyn() { _ese507_scr ssh_vsyn "$@"; }
plot() { _ese507_scr ssh_plot "$@"; }

export _ESE507_SCR
export -f _ese507_scr link vlog vsim vsyn plot 2>/dev/null || true

echo "Aliases loaded:  link  vlog  vsim  vsyn  plot"
