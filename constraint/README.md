`constraint/all_config.json` is the only file to edit. `vlog`, `vsim`, `vsyn`, and `link` read it.

- `design` (`WIDTH`, `ACCW`, `PIPELINED`, `R`, `C`, `K`) is written to `rtl/param.sv`. `vlog` compiles this first. The testbench reads `PIPELINED` to choose `mac` (0) or `mac_pipe` (1). `input_mems_tb` reads `R`, `C`, and `K` from that package.
- `sim.TVALID_PROB`, `sim.TREADY_PROB`, and `sim.STAGE` stay in this file. `vsim` passes `TVALID_PROB` and `STAGE` to `input_mems_tb`. `Conv_tb` reads `TVALID_PROB` and `TREADY_PROB` from `params.sv`. A probability of `0` randomizes that rate. `STAGE` is `1`, `2`, or `3`.
- `syn` (clock, reset, period) is written into `syn/runsynth.tcl` on CAD by `vsyn`. `link` does not copy `sim/` or `syn/`.

`sim.seed` is the default `-sv_seed`. `vsyn --clk`, `--rst`, and `--period` write back into this JSON.

`scr/libaray/cad_common.sh` is the shared host library. `scr/libaray/remote.py` runs on CAD: it writes `sim/part2/params.sv` and `sim/part3/params.sv`, runs `vlog` and console `vsim`, fills `syn/runsynth.tcl`, and runs `dc_shell -f runsynth.tcl`.
