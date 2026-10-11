# Waveforms for an interactive Questa session of mac_tb. Console `vsim` does not source this file.
onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /mac_tb/clk
add wave -noupdate /mac_tb/init_value
add wave -noupdate /mac_tb/init_acc
add wave -noupdate /mac_tb/input_valid
add wave -noupdate /mac_tb/input0
add wave -noupdate /mac_tb/input1
add wave -noupdate /mac_tb/Q
add wave -noupdate /mac_tb/out
add wave -noupdate /mac_tb/out_exp
add wave -noupdate /mac_tb/out_exp_d
add wave -noupdate /mac_tb/reset
add wave -noupdate /mac_tb/errors
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
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
WaveRestoreZoom {0 ns} {1 us}
