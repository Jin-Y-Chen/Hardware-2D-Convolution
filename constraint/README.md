Shared compile-time defines for sim and syn.

`constraint/param/params.sv` is the only copy. `genParams1` writes it; `vlog` / `vsim` / `vsyn` include it from here.
