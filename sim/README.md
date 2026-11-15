Simulation support, in the same part folders as `rtl/` and `tb/`.

Run simulation from the repository root with `vsim`. `Conv_tb` runs `sim/part3/simParams3_xrun` on CAD. That script fills `params.sv` from the values `vsim` passes out of `constraint/all_config.json`, then compiles the `rtl/` and `tb/` sources with `xrun`.

```bash
source scr/env.sh
vsim mac_tb mac
```

**part1:**

| File | Role |
| --- | --- |
| `mac_tb.sv` | Course testbench. Reads `sim/part1/params.sv`, which `vsim` writes from `constraint/all_config.json`. |
| `mac_tb.c` | DPI model of the expected MAC result, called from `mac_tb.sv`. |
| `genParams1` | Writes `` `define `` values into `params.sv` (WIDTH, ACCW, PIPELINED). |
| `simParams1` | Calls `genParams1`, then `vlog` and `vsim` in this directory on CAD. |
| `wave.do` | Waveform list for an interactive Questa session. Console `vsim` does not load it. |

The `vsim` command from `scr/env.sh` does not run these scripts. It compiles `sim/part1/params.sv` plus the DUT and testbench under `rtl/` and `tb/`.
