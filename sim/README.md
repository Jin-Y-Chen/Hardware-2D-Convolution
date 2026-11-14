Simulation support, in the same part folders as `rtl/` and `tb/`.

Run simulation from the repository root with `vsim`. It compiles the DUT and testbench against `rtl/param.sv` (from `constraint/all_config.json`) and runs on CAD.

```bash
source scr/env.sh
vsim mac_tb mac
```

**part1:**

| File | Role |
| --- | --- |
| `mac_tb.sv` | Course testbench. Expects `params.sv` from `genParams1`, not `rtl/param.sv`. |
| `mac_tb.c` | DPI model of the expected MAC result, called from `mac_tb.sv`. |
| `genParams1` | Writes `` `define `` values into `params.sv` (WIDTH, ACCW, PIPELINED). |
| `simParams1` | Calls `genParams1`, then `vlog` and `vsim` in this directory on CAD. |
| `wave.do` | Waveform list for an interactive Questa session. Console `vsim` does not load it. |

The `vsim` command from `scr/env.sh` does not run these scripts. It compiles `rtl/param.sv` plus the DUT and testbench under `rtl/` and `tb/`.
