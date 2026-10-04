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
vlog
vsim mac_tb mac
vsyn mac
```

```text
scr/
├── env.sh
├── ssh_link     push rtl tb sim syn constraint; pull log
├── ssh_vlog     compile
├── ssh_vsim     simulate in the console
├── ssh_vsyn     dc_shell -f runsynth.tcl
└── libaray/
    ├── cad_common.sh
    └── remote.py
```

`link` is the only command that syncs the project tree. `vlog` compiles on CAD and uploads only the generated `rtl/param.sv`. `vsim` and `vsyn` compile with that same step, then simulate or run `syn/runsynth.tcl`. Tool output is printed in the console and saved under `log/`.

`PIPELINED` is `0` for `mac` and `1` for `mac_pipe`. A wrong mix prints one line, for example `vsim mac_tb mac` or `Set design.PIPELINED to 0 in constraint/all_config.json for mac.`
