@echo off
REM Windows CMD aliases for this repo. Run once per CMD session from repo root:
REM   scr\aliases.cmd
REM Then:  sync    sim    syn

set "SCR=%~dp0"
set "SCR=%SCR:~0,-1%"

doskey sync=bash "%SCR%\ssh_rsync" $*
doskey sim=bash "%SCR%\remote_sim" $*
doskey syn=bash "%SCR%\remote_syn" $*

echo Aliases loaded:  sync  sim  syn
