#!/usr/bin/env bash
# source scr/env.sh
#   link   vlog   vsim   vsyn
# Functions (not aliases) so they override /usr/bin/link and other PATH tools.
# Drop leftover aliases from an older env.sh — bash cannot redefine an alias as a function.
unalias link vlog vsim vsyn sync sim syn 2>/dev/null || true

_ese507_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

_ese507_scr() {
    local root
    root="$(_ese507_root)" || {
        echo "Not inside the Hardware-2D-Convolution repo." >&2
        return 1
    }
    "$root/scr/$1" "${@:2}"
}

link() { _ese507_scr ssh_link "$@"; }
vlog() { _ese507_scr ssh_vlog "$@"; }
vsim() { _ese507_scr ssh_vsim "$@"; }
vsyn() { _ese507_scr ssh_vsyn "$@"; }
