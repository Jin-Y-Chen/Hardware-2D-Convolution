#!/usr/bin/env bash
# source scr/env.sh
# Then:  link  vlog  vsim  vsyn  pdata  pplot

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "source this file:  source scr/env.sh" >&2
    exit 1
fi

unalias link vlog vsim vsyn plot pdata pplot 2>/dev/null || true
unset -f plot 2>/dev/null || true

_ESE507_SCR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run a scr/ script in its own bash so its set -e does not affect this shell.
_ese507_scr() {
    local cmd="$1"
    shift
    bash "$_ESE507_SCR/$cmd" "$@"
}

link() { _ese507_scr ssh_link "$@"; }
vlog() { _ese507_scr ssh_vlog "$@"; }
vsim() { _ese507_scr ssh_vsim "$@"; }
vsyn() { _ese507_scr ssh_vsyn "$@"; }
pdata() { _ese507_scr csv_data "$@"; }
pplot() { _ese507_scr csv_plot "$@"; }

export _ESE507_SCR
export -f _ese507_scr link vlog vsim vsyn pdata pplot 2>/dev/null || true

echo "Aliases loaded:  link  vlog  vsim  vsyn  pdata  pplot"
