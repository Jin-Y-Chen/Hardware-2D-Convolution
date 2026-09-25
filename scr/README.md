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

### Remote Server

The remote server requires:

* SSH access to `eceap1`
* `rsync` installed
* Required simulation/emulation tools
* Required synthesis tools

### SSH Configuration

Add the following to `~/.ssh/config`. Do not put a password in this repository or in any script.

```sshconfig
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

### SSH Key Setup

If an SSH key has not already been created:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_sbu
ssh-copy-id -i ~/.ssh/id_ed25519_sbu.pub eceap1
```

Load the key into the SSH agent:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_sbu
```

## Functional Example

From the repository root, make the scripts executable and load the environment:

```bash
chmod +x scr/ssh_rsync scr/remote_sim scr/remote_syn
sed -i 's/\r$//' scr/ssh_rsync scr/env.sh

source scr/env.sh
```

The repository is organized so that RTL is developed locally and simulation/synthesis are performed remotely:

```text
repository/
├── rtl/
│   └── ...
└── scr/
    ├── env.sh
    ├── ssh_rsync
    ├── remote_sim
    └── remote_syn
```

After modifying the RTL under `rtl/`, synchronize it to the remote server:

```bash
sync
```

Run the remote simulation:

```bash
sim
```

Run synthesis:

```bash
syn
```

A typical development cycle is therefore:

```bash
source scr/env.sh

# Edit RTL
vim rtl/...

# Copy RTL to eceap1
sync

# Run simulation
sim

# Run synthesis
syn
```

The scripts handle the remote file synchronization and execution, so the normal workflow remains:

```text
Local Repository
      │
      │ edit
      ▼
    rtl/
      │
      │ sync
      ▼
eceap1:/.../rtl/
      │
      ├── sim
      │
      └── syn
```
