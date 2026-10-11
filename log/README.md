Tool output log and working files.

These are copied back from CAD after each remote run. They are generated; do not edit by hand. Design Compiler also writes `syn/command.log` and `syn/default.svf`; those stay in `syn/`.

| File | From | What to check |
|---|---|---|
| `vlog.log` | `vlog` / `ssh_vlog` | last line `Errors: 0` |
| `vsim.log` | `vsim` / `ssh_vsim` | testbench transcript |
| `vsyn.log` | `vsyn` / `ssh_vsyn` | Design Compiler / `report_qor` |
