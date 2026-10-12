onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /input_mems_tb/STAGE
add wave -noupdate /param::WIDTH
add wave -noupdate /param::C
add wave -noupdate /param::R
add wave -noupdate /param::K
add wave -noupdate /input_mems_tb/clk
add wave -noupdate /input_mems_tb/reset
add wave -noupdate /input_mems_tb/dut/state
add wave -noupdate /input_mems_tb/dut/next_state
add wave -noupdate /input_mems_tb/INPUT_TDATA
add wave -noupdate /input_mems_tb/INPUT_TVALID
add wave -noupdate /input_mems_tb/INPUT_TUSER
add wave -noupdate /input_mems_tb/INPUT_TREADY
add wave -noupdate /input_mems_tb/errors
add wave -noupdate /input_mems_tb/inputs_loaded
add wave -noupdate /input_mems_tb/compute_finished
add wave -noupdate /input_mems_tb/S
add wave -noupdate /input_mems_tb/B
add wave -noupdate /input_mems_tb/Q
add wave -noupdate /input_mems_tb/X_read_addr
add wave -noupdate /input_mems_tb/dut/X_mem_addr
add wave -noupdate /input_mems_tb/X_data
add wave -noupdate /input_mems_tb/W_read_addr
add wave -noupdate /input_mems_tb/dut/W_mem_addr
add wave -noupdate /input_mems_tb/W_data
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {69 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 299
configure wave -valuecolwidth 115
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {100 ns}
