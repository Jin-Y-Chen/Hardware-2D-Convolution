#!/usr/bin/env bash
# Git Bash / WSL aliases. From repo root or any subdir:
#   source scr/env.sh
#   sync
#   sim
#   syn

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

alias sync='_ese507_scr ssh_rsync'
alias sim='_ese507_scr remote_sim'
alias syn='_ese507_scr remote_syn'
