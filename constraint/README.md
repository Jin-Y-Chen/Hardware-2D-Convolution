`constraint/all_config.json` is the only file to edit. `vlog`, `vsim`, `vsyn`, and `link` read it.

- `design` (`WIDTH`, `ACCW`, `PIPELINED`) is written to `rtl/param.sv`. `vlog` compiles this first. The testbench reads `PIPELINED` to choose `mac` (0) or `mac_pipe` (1).
- `syn` (clock, reset, period, I/O delay) is written into `syn/runsynth.tcl` by `vsyn`.

`sim.seed` is the default `-sv_seed`. `vsyn --clk`, `--rst`, and `--period` write back into this JSON.

`scr/libaray/cad_common.sh` is the shared host library. `scr/libaray/remote.py` runs on CAD: `vlog`, console `vsim`, and `dc_shell -f runsynth.tcl`.
