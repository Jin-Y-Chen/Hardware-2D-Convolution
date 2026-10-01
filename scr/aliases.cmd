@echo off
REM Windows CMD:  scr\aliases.cmd
REM WSL / Linux:  source scr/env.sh
REM Then:  link    vlog    vsim    vsyn

set "SCR=%~dp0"
set "SCR=%SCR:~0,-1%"

doskey link=bash "%SCR%\ssh_link" $*
doskey vlog=bash "%SCR%\ssh_vlog" $*
doskey vsim=bash "%SCR%\ssh_vsim" $*
doskey vsyn=bash "%SCR%\ssh_vsyn" $*

echo Aliases loaded:  link  vlog  vsim  vsyn
