Synthesis scripts and the generated netlist.

`vsyn <top>` compiles that DUT, fills `TOP_MOD_NAME`, `SRC_FILE`, and the clock settings in `runsynth.tcl` from `constraint/all_config.json`, and runs `dc_shell -f runsynth.tcl` on CAD. `setupdc.tcl` is the course library setup and stays on CAD.

Pulled back after a run:

| File | What it is |
|---|---|
| `gates.v` | synthesized netlist |
| `command.log` | Design Compiler command transcript |
| `default.svf` | Formality setup written by DC |
