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

* SSH access to CAD (`lab40`; Questa / DC). Tools are on **CAD**, not eceap1
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
chmod +x scr/ssh_link scr/ssh_vlog scr/ssh_vsim scr/ssh_vsyn scr/ssh_plot
sed -i 's/\r$//' scr/ssh_link scr/ssh_vlog scr/ssh_vsim scr/ssh_vsyn scr/ssh_plot scr/env.sh scr/cad_common.sh

source scr/env.sh
```

`link` / `vlog` / `vsim` / `vsyn` / `plot` are **functions** from that `source`. If you skip it, `link` is some other program (`Usage: link FILE1 FILE2`). After `source`, `type link` should show `link is a function`.

Without sourcing, run `./scr/ssh_link`.

```text
scr/
├── env.sh
├── cad_common.sh      shared CAD setup
├── ssh_link           rtl/ tb/ sim/ syn/ constraint/ host-master; log/ from CAD  (command: link)
├── ssh_vlog           Questa compile  (command: vlog)
├── ssh_vsim           Questa simulate (command: vsim)
├── ssh_vsyn           Design Compiler (command: vsyn)
├── ssh_plot           scan log/vsyn.log → data/part/<top>.csv (command: plot)
└── plot/
    └── table.py       pandas/csv upsert used by plot
```

Typical cycle:

```bash
source scr/env.sh
link          # rtl/, tb/, sim/, syn/, constraint/, log/
vsim mac_tb_mod mac_pipe   # or: vsim mac_tb mac
vsyn mac
plot          # CSV from log/vsyn.log → data/part/mac.csv
```

```text
Host  rtl/  --push-->  CAD:~/ese507/project/rtl/
Host  tb/   --push-->  CAD:~/ese507/project/tb/
Host  sim/  --push-->  CAD:~/ese507/project/sim/
Host  syn/  --push-->  CAD:~/ese507/project/syn/
Host  constraint/ --push-->  CAD:~/ese507/project/constraint/
                 then pull new filenames only
CAD:~/ese507/project/log/  --pull-->  Host log/   (overwrite transcripts)
```

### link

`rtl/`, `tb/`, `sim/`, `syn/`, and `constraint/`: host is master.

* **Push:** same-name files on CAD are replaced with the host copy
* **Pull:** only files with a new / different name (host files are never overwritten)
* Skips `tb/README.md`
* Never copies `work/`, waves, or other tool junk from `rtl/` / `tb/` / `sim/` / `syn/`
* No `--delete` on push, so a new file created on CAD can be pulled

`log/`: CAD is master (host only reads). `link` does not push logs; it overwrites local `log/*.log` from `~/ese507/project/log/`. Skips `log/README.md`.

### vlog

```bash
vlog mac
vlog mac_pipe
vlog --list
vlog --all
```

### params.sv and seed

Edit `constraint/param/params.sv`, then **`link`** (vsim does not copy this file):

```text
`define WIDTHVAL 16
`define ACCWVAL 48
`define PIPELINEDVAL 0
`define SEEDVAL random
```

`SEEDVAL` is `random` or a number from Questa’s `Sv_Seed = …` line so you can replay a failing run. `mac_tb` includes this file; `vsim` / `simParams1` pass it as `-sv_seed`.

On CAD you can also write the file with `./sim/part1/genParams1 WIDTH ACCW PIPE [SEED]` (keeps the old seed unless you pass a fourth argument).

### vsim

Batch only (`vsim -c`). First argument is the testbench, second is the DUT. Remote `PIPELINEDVAL` is set from the DUT (`mac` → 0, `mac_pipe` → 1).

```bash
vsim                        # list tops and DUTs
vsim mac_tb mac
vsim mac_tb mac_pipe
vsim mac_tb_mod mac
vsim mac_tb_mod mac_pipe
```

`log/vsim.log` is the course header, then each cycle (`reset`, `init_acc`, `input_valid`, `Q`, `input0`, `input1`, `init_value`, `acc_w`, `out`, `out_exp_d`, `out_exp`, C `accum` / `shift_r1`) with decimal and hex, then:

```text
[VALID] / [INVALID] summary
  pass / fail / total
  match = pass/total %
```

On CAD, from `sim/part1` (TB is `../../tb/part1/`, RTL is `../../rtl/`):

```bash
./simParams1 16 48 0 0           # batch
./simParams1 16 48 0 1 &         # GUI
```

Change widths or seed, then:

```bash
# edit constraint/param/params.sv  or  ./sim/part1/genParams1 16 48 0 1896683400
link
vsim mac_tb_mod mac
```

### vsyn

RTL only (no testbench). `vsyn <top>` writes `syn/runsynth.tcl` then runs it on CAD.

```bash
vsyn mac
vsyn mac_pipe
```

`log/vsyn.log` is the DC transcript. `vsyn` does not write CSVs.

### plot

Host-only. Reads `log/vsyn.log` and upserts `data/part/<top>.csv`.

```bash
plot
```
