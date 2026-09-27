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
link
vlog part1/mac.sv
vsim mac_tb
vsyn --top mac part1/mac.sv
```

```text
Host  rtl/  --push-->  lab40:~/ese507/project/rtl/
Host  tb/   --push-->  lab40:~/ese507/project/tb/
                 then pull (host files are never overwritten)
                          ├── vlog   ->  log/vlog.log   (also on compile fail)
                          ├── vsim   ->  log/vsim.log
                          └── vsyn   ->  log/vsyn.log
```

### link

Host is master: **push** both trees, then **pull** with `--ignore-existing`.

* Syncs `rtl/` and `tb/` to `~/ese507/project/{rtl,tb}`
* Skips `tb/README.md`
* Never copies `work/`, waves, transcripts, or other tool junk
* `--delete` on push so remote leftovers go away

### vlog

Paths are under `rtl/` or `tb/` (prefixes optional).

```bash
vlog --list
vlog part1/mac.sv
vlog part1/mac.sv tb/part1/mac_tb.sv tb/part1/mac_tb.c
vlog --all
```

Edit `tb/part1/params.sv`, then `link`, then `vsim`. `vsim` does not copy params; `mac_tb` includes the file already on lab40.

### vsim

`vsim` recompiles RTL or `tb/` that are missing from `work/` or newer than the last compile (typical after `link`).

```bash
vsim mac_tb
```

Batch only (`vsim -c`). Cycle dumps are in the transcript / `log/vsim.log` (`TRACE` in `mac_tb.sv`).

Change WIDTH/ACCW/PIPELINED, then:

```bash
./tb/part1/simParams1 8 24 0    # write params.sv only
link
vsim mac_tb
```

### vsyn

RTL only (no testbench).

```bash
vsyn part1/mac.sv
vsyn --top mac part1/mac.sv
```
