Synthesis scripts and the generated netlist.

`vsyn <top>` compiles that DUT, fills `TOP_MOD_NAME`, `SRC_FILE`, and `CLK_PERIOD` in `runsynth.tcl`, and runs `dc_shell -f runsynth.tcl` on CAD. `CLK_NAME`, `RST_NAME`, and `IO_DELAY` stay in that file. `link` copies `runsynth.tcl`, `setupdc.tcl`, and `README.md` to CAD, and copies `gates.v` back.

| File | What it is |
|---|---|
| `runsynth.tcl` | synthesis script, pushed by `link` |
| `setupdc.tcl` | course library setup, pushed by `link` |
| `README.md` | this note, pushed by `link` |
| `gates.v` | synthesized netlist, pulled by `link` |
