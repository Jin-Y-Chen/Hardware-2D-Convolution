##############################################
# Setup: vsyn <top> fills these for the current top.
# SRC_FILE paths are relative to syn/.
set TOP_MOD_NAME "mac_pipe";
set SRC_FILE [list "../rtl/param.sv" "../rtl/part1/mac_pipe.sv"];
# Multiple sources: set SRC_FILE [list "file1.sv" "file2.sv"];
###############################################

# Clock, reset, and period. vsyn fills these from constraint/all_config.json.
# IO_DELAY stays in this file.
set CLK_NAME   "clk";
set RST_NAME   "reset";
set CLK_PERIOD 1.3;
set IO_DELAY   0.08;

# setup
source setupdc.tcl
set search_path [concat ../rtl ../rtl/part1 . $search_path]
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
# WIDTH / ACCW default to the param package (rtl/param.sv)
elaborate -work WORK $TOP_MOD_NAME

###### CLOCKS AND PORTS #######
set CLK_PORT [get_ports $CLK_NAME]
set TMP1 [remove_from_collection [all_inputs] $CLK_PORT]
set INPUTS [remove_from_collection $TMP1 $RST_NAME]
create_clock -period $CLK_PERIOD $CLK_PORT
set_input_delay $IO_DELAY -max -clock $CLK_NAME $INPUTS
set_output_delay $IO_DELAY -max -clock $CLK_NAME [all_outputs]


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

