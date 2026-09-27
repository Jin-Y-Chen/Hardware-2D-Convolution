## Prerequisites

### Local WSL / Linux

The local development environment requires:

* Git
* OpenSSH (`ssh`)
* `rsync`
* Bash

On Ubuntu/WSL, install the required packages with:

```bash
sudo apt update
sudo apt install git openssh-client rsync
```

Git Bash does not ship `rsync`. If you run `link` from Git Bash, the scripts re-launch themselves in WSL. Prefer WSL:

```bash
wsl
cd /mnt/c/Users/Jin/Documents/Github/Hardware-2D-Convolution
source scr/env.sh
```

### Remote Server

The remote server requires:

* SSH access to `lab40` (Questa / DC). Tools are on **lab40**, not eceap1
* `rsync` installed
* Course setup: `source ~/ese507setup-csh` (or `ese507setup-bash` — the scripts do this)

### SSH Configuration

Add the following to `~/.ssh/config`. Do not put a password in this repository or in any script.

```sshconfig
Host lab40
    HostName lab40.ece.stonybrook.edu
    User jinchen
    IdentityFile ~/.ssh/id_ed25519_sbu
    IdentitiesOnly yes
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 4h

Host eceap1
    HostName eceap1.ece.stonybrook.edu
    User jinchen
    ProxyJump lab40
    IdentityFile ~/.ssh/id_ed25519_sbu
    IdentitiesOnly yes
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 4h
```

### SSH Key Setup

If an SSH key has not already been created:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_sbu
ssh-copy-id -i ~/.ssh/id_ed25519_sbu.pub lab40
```

Load the key into the SSH agent:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_sbu
```

## Commands

From the repository root:

```bash
chmod +x scr/ssh_link scr/ssh_vlog scr/ssh_vsim scr/ssh_vsyn
sed -i 's/\r$//' scr/ssh_link scr/ssh_vlog scr/ssh_vsim scr/ssh_vsyn scr/env.sh scr/cad_common.sh

source scr/env.sh
```

`link` / `vlog` / `vsim` / `vsyn` are **functions** from that `source`. If you skip it, `link` is some other program (`Usage: link FILE1 FILE2`). After `source`, `type link` should show `link is a function`.

Without sourcing, run `./scr/ssh_link`.

```text
scr/
├── env.sh
├── cad_common.sh      shared lab40 / CAD setup
├── ssh_link           host-master rtl/ and tb/  (command: link)
├── ssh_vlog           Questa compile  (command: vlog)
├── ssh_vsim           Questa simulate (command: vsim)
└── ssh_vsyn           Design Compiler (command: vsyn)
```

Typical cycle:

```bash
source scr/env.sh
link          # rtl/ and tb/ (including params.sv)
vsim mac_tb   # compile + batch sim; transcript -> log/vsim.log
vsyn --top mac part1/mac.sv
```

```text
Host  rtl/  --push-->  lab40:~/ese507/project/rtl/
Host  tb/   --push-->  lab40:~/ese507/project/tb/
                 then pull new filenames only
                          ├── vlog   ->  log/vlog.log
                          ├── vsim   ->  log/vsim.log
                          └── vsyn   ->  log/vsyn.log
```

### link

Host is master.

* **Push:** same-name files on lab40 are replaced with the host copy
* **Pull:** only files with a new / different name (host files are never overwritten)
* Skips `tb/README.md`
* Never copies `work/`, waves, transcripts, or other tool junk
* No `--delete` on push, so a new file created on lab40 can be pulled

### vlog

Paths are under `rtl/` or `tb/` (prefixes optional).

```bash
vlog --list
vlog part1/mac.sv
vlog part1/mac.sv tb/part1/mac_tb.sv tb/part1/mac_tb.c
vlog --all
```

### params.sv and seed

Edit `tb/part1/params.sv`, then **`link`** (vsim does not copy this file):

```text
`define WIDTHVAL 16
`define ACCWVAL 48
`define PIPELINEDVAL 0
`define SEEDVAL random
```

`SEEDVAL` is `random` or a number from Questa’s `Sv_Seed = …` line so you can replay a failing run. `mac_tb` includes this file; `vsim` / `simParams1` pass it as `-sv_seed`.

On lab40 you can also write the file with `./tb/part1/genParams1 WIDTH ACCW PIPE [SEED]` (keeps the old seed unless you pass a fourth argument).

### vsim

Batch only (`vsim -c`). Rebuilds `work/` and compiles from `tb/part1` so `` `include "params.sv" `` hits the linked file. RTL is `../../rtl/param_pkg.sv` and `../../rtl/part1/*.sv`. Transcript is stripped of the Questa banner and copied to `log/vsim.log`.

```bash
vsim mac_tb
vsim --seed 1896683400 mac_tb    # optional override of SEEDVAL
```

`log/vsim.log` is the course header, then each cycle (`reset`, `init_acc`, `input_valid`, `Q`, `input0`, `input1`, `init_value`, `acc_w`, `out`, `out_exp_d`, `out_exp`, C `accum` / `shift_r1`) with decimal and hex, then:

```text
[VALID] / [INVALID] summary
  pass / fail / total
  match = pass/total %
```

On lab40, from `tb/part1` (RTL paths are under `../../rtl/`):

```bash
./simParams1 16 48 0 0           # batch
./simParams1 16 48 0 1 &         # GUI
```

Change widths or seed, then:

```bash
# edit tb/part1/params.sv  or  ./tb/part1/genParams1 16 48 0 1896683400
link
vsim mac_tb
```

### vsyn

RTL only (no testbench).

```bash
vsyn part1/mac.sv
vsyn --top mac part1/mac.sv
```
