Testbenches used by the simulator. Same part folders as `rtl/` (`part1/`, later part2–4). Synced to CAD with `link` (`tb/README.md` is host-only).

**part1:** `mac_tb.sv`, `mac_tb.c`, `mac_tb_mod.sv`, `mac_tb_mod.c`

WIDTH / ACCW / PIPELINED come from `rtl/param.sv`, which `vlog` generates from `design` in `constraint/all_config.json`. `PIPELINED` selects `mac` (0) or `mac_pipe` (1).
