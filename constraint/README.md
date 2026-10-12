`constraint/all_config.json` is the only file to edit. `vlog`, `vsim`, `vsyn`, and `link` read it.

- `design` (`WIDTH`, `ACCW`, `PIPELINED`, `R`, `C`, `K`) is written to `rtl/param.sv`. `vlog` compiles this first. The testbench reads `PIPELINED` to choose `mac` (0) or `mac_pipe` (1). `input_mems_tb` reads `R`, `C`, and `K` from that package.
- `sim.TVALID_PROB` and `sim.STAGE` stay in this file. `vsim` passes them to `input_mems_tb`. `TVALID_PROB` of `0` randomizes the input valid rate. `STAGE` is `1`, `2`, or `3`.
- `syn` (clock, reset, period, I/O delay) is written into `syn/runsynth.tcl` by `vsyn`.

`sim.seed` is the default `-sv_seed`. `vsyn --clk`, `--rst`, and `--period` write back into this JSON.

`scr/libaray/cad_common.sh` is the shared host library. `scr/libaray/remote.py` runs on CAD: `vlog`, console `vsim`, and `dc_shell -f runsynth.tcl`.
