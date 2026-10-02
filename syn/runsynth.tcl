##############################################
# Setup: vsyn <top> fills these for the current top.
# Clock period is ns. SRC_FILE paths are relative to syn/.
set CLK_NAME "clk";
set CLK_PERIOD 1;
set RST_NAME "reset";
set TOP_MOD_NAME "mac_pipe";
set P_WIDTH 16;
set P_ACCW 48;
set SRC_FILE [list "../rtl/param_pkg.sv" "../rtl/part1/mac_pipe.sv"];
# Multiple sources: set SRC_FILE [list "file1.sv" "file2.sv"];
###############################################

# setup
source setupdc.tcl
# params.sv lives in constraint/param (not next to the RTL).
set search_path [concat ../constraint/param ../rtl ../rtl/part1 . $search_path]
set hdlin_include_dir_path "../constraint/param ../rtl ."
file mkdir work_synth
date
pid
pwd
getenv USER
catch {getenv HOSTNAME}


# optimize FSMs
set fsm_auto_inferring "true"; 
set fsm_enable_state_minimization "true";

define_design_lib WORK -path work_synth
analyze $SRC_FILE -format sverilog
# Module defaults in mac.sv are not the constraint file; pass WIDTH/ACCW from params.sv.
elaborate -work WORK $TOP_MOD_NAME -parameters "WIDTH=$P_WIDTH,ACCW=$P_ACCW"

###### CLOCKS AND PORTS #######
set CLK_PORT [get_ports $CLK_NAME]
set TMP1 [remove_from_collection [all_inputs] $CLK_PORT]
set INPUTS [remove_from_collection $TMP1 $RST_NAME]
create_clock -period $CLK_PERIOD $CLK_PORT
set_input_delay 0.08 -max -clock $CLK_NAME $INPUTS
set_output_delay 0.08 -max -clock $CLK_NAME [all_outputs]


###### OPTIMIZATION #######
set_max_area 0 

###### RUN #####
compile_ultra
report_area
report_power
report_timing
report_timing -loops
date
write -f verilog $TOP_MOD_NAME -output gates.v -hierarchy

quit

