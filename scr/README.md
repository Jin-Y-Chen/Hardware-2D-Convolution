scripts that facilitate, manage, and run directory and file navigation

Remote Development Workflow

Prerequisites

Local Windows

- Git Bash or WSL
- OpenSSH (`ssh`)
- rsync

Verify:

```
ssh -V
rsync --version
```

If using WSL:

```
sudo apt update
sudo apt install rsync
```

Remote Server

- SSH access to eceap1
- rsync installed
- Required simulation/emulation tools
- Required synthesis tools

Verify SSH:

```
ssh eceap1
```

Verify remote rsync:

```
ssh eceap1 'rsync --version'
```

SSH Configuration

Add the following to `~/.ssh/config`. Do not put a password in this repo or in any script.

```
Host eceap1
    HostName eceap1.ece.stonybrook.edu
    User jinchen
    ProxyJump lab40.ece.stonybrook.edu
    IdentityFile ~/.ssh/id_ed25519_sbu
    IdentitiesOnly yes
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 4h
```

One-time key setup (Git Bash or WSL):

```
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_sbu
ssh-copy-id -i ~/.ssh/id_ed25519_sbu.pub eceap1
```

Load the key once per login:

```
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_sbu
```

Test:

```
ssh eceap1
```

Setup

From the repository root:

```
chmod +x scr/ssh_rsync scr/remote_sim scr/remote_syn
sed -i 's/\r$//' scr/ssh_rsync scr/env.sh
```

Command aliases

Short names map straight to files in `scr/`. There is no dispatcher.

| Alias | Script |
|---|---|
| `sync` | `scr/ssh_rsync` — copy `rtl/` to eceap1 |
| `sim` | `scr/remote_sim` |
| `syn` | `scr/remote_syn` |

**Git Bash / WSL** (once per session, or add to `~/.bashrc`):

```
source scr/env.sh
sync
```

**Windows CMD** (once per session):

```
scr\aliases.cmd
sync
```

Without aliases you can still run the scripts by path: `./scr/ssh_rsync`.

Workflow

Edit RTL locally:

```
rtl/
```

Sync, then remote sim / synth:

```
source scr/env.sh
sync
sim
syn
```

Workflow Summary

```
Local Git Repository
        │
        ├── Edit rtl/
        │
        ├── sync     (alias -> scr/ssh_rsync)
        │              SSH + rsync
        │              ▼
        │           eceap1 / rtl/
        │
        ├── sim      (alias -> scr/remote_sim)
        │
        └── syn      (alias -> scr/remote_syn)
```

GitHub is used for version control. Remote synchronization is handled directly through SSH/rsync. Use an SSH key, never a saved password.
