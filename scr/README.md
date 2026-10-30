## Prerequisites

Local: Git, OpenSSH, `rsync`, Bash, `python3` 3.7+.

```bash
sudo apt install git openssh-client rsync python3
```

CAD is `lab40.ece.stonybrook.edu` through `eceap1`. The login sources `~/ese507setup-csh` and runs `scr/libaray/remote.py`. Match that host name in `~/.ssh/config`.

```sshconfig
Host eceap1
    HostName eceap1.ece.stonybrook.edu
    User jinchen

Host lab40 lab40.ece.stonybrook.edu
    HostName lab40.ece.stonybrook.edu
    User jinchen
    ProxyJump eceap1
```

## Commands

```bash
source scr/env.sh
link
vlog [DUT]
vsim [TOP] [DUT]
vsyn [TOP]
pdata
pplot mac freq_MHz area_um2 MET
```

```text
scr/
├── env.sh
├── ssh_link     push rtl tb; pull log. sim and syn stay on CAD
├── ssh_vlog     compile
├── ssh_vsim     simulate in the console
├── ssh_vsyn     dc_shell -f runsynth.tcl
├── csv_data     pdata
├── csv_plot     pplot
└── libaray/
    ├── cad_common.sh
    ├── remote.py
    ├── table.py
    └── plot.py
```

`link` syncs `rtl/` and `tb/` only, then overwrites `log/`. `sim/` and `syn/` stay on CAD, so this machine does not need those folders. `vlog` compiles on CAD, uploads `rtl/param.sv`, and writes `sim/part2/params.sv` and `sim/part3/params.sv` there. `vsim` and `vsyn` compile with that same step. `vsyn` then fills `syn/runsynth.tcl` on CAD and runs it. Tool output is printed in the console and saved under `log/`.

`PIPELINED` is `0` for `mac` and `1` for `mac_pipe`. A wrong mix prints `Set design.PIPELINED to 0 in constraint/all_config.json for mac.` A bad `vlog`, `vsim`, or `vsyn` command prints that command's help.

`vsim [TOP] [DUT]` for `input_mems` reads `design.WIDTH`, `R`, `C`, and `K` from `rtl/param.sv`. `sim.TVALID_PROB` and `sim.STAGE` stay in `constraint/all_config.json` and are passed to the testbench.

`vlog Conv`, `vsim Conv_tb Conv`, and `vsyn Conv` compile `rtl/part3/input_mems.sv`, `mac_pipe.sv`, `fifo_out.sv`, and `Conv.sv`. `Conv_tb` also compiles `tb/part4/test_helper.c`. `sim.TVALID_PROB` and `sim.TREADY_PROB` are written into `params.sv` as `TVPR` and `TRPR`.

## pdata

`pdata` runs on this machine. It reads `log/vsyn.log` and `rtl/param.sv`, then writes one row to `data/part1/<design>.csv` (`mac`, `mac_pipe`), `data/part2/input_mems.csv`, or `data/part3/Conv.csv`. The design name is `TOP_MOD_NAME` from the log. A later run with the same design, `WIDTH`, `ACCW`, and period replaces that row. Pass a log path to read a file other than `log/vsyn.log`.

```bash
vsyn mac
pdata
pdata log/vsyn.log
```

A line like `data/part1/mac.csv  mac  10 ns  MET  12 rows` means the table was updated. Columns are `design`, `width`, `accw`, `period_ns`, `freq_MHz`, `area_um2`, `dyn_uw`, `leak_uw`, `total_uw`, `slack_ns`, `timing`, `path_start`, `path_end`.

## pplot

`pplot` scatters two of those columns. The file argument is a name under `data/part1`, `data/part2`, or `data/part3` (`mac` is `data/part1/mac.csv`, `Conv` is `data/part3/Conv.csv`) or a path to a CSV. `MET` keeps only rows whose `timing` column is `MET`. One file writes the PDF next to that CSV. A bracket list shares one graph, named from every file.

```bash
pplot mac freq_MHz area_um2 MET
pplot [mac, mac_pipe] freq_MHz total_uw MET
```

Axis labels use letter units: Frequency (MHz), Area (um2), Total power (uW), and the same form for `dyn_uw`, `leak_uw`, `period_ns`, and `slack_ns`. Any other column name is used as the axis label. Run `pdata` first if the CSV is missing.
