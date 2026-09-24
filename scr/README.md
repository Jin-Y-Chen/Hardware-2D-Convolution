Remote Development Workflow
Prerequisites
Local Windows

Git Bash or WSL

OpenSSH (ssh)

rsync

Verify:

ssh -V
rsync --version


If using WSL:

sudo apt update
sudo apt install rsync

Remote Server

SSH access to eceap1

rsync installed

Required simulation/emulation tools

Required synthesis tools

Verify SSH:

ssh eceap1


Verify remote rsync:

ssh eceap1 'rsync --version'

SSH Configuration

Add the following to ~/.ssh/config:

Host eceap1
    HostName eceap1.ece.stonybrook.edu
    User jinchen
    ProxyJump lab40.ece.stonybrook.edu


Test:

ssh eceap1

Setup

From the repository root:

chmod +x scr/ssh_rsync
chmod +x scr/remote_sim
chmod +x scr/remote_syn

Workflow

Edit RTL locally:

rtl/


Sync changes to the remote server:

sed -i 's/\r$//' scr/ssh_rsync

./scr/ssh_rsync


Run simulation and compliance checks remotely:

./scr/remote_sim


Run synthesis remotely:

./scr/remote_syn

Workflow Summary
Local Git Repository
        │
        ├── Edit rtl/
        │
        ├── ./scr/ssh_rsync
        │          │
        │          │ SSH + rsync
        │          ▼
        │      eceap1
        │          │
        │          └── Updated rtl/
        │
        ├── ./scr/remote_sim
        │          │
        │          └── Simulation + compliance
        │
        └── ./scr/remote_syn
                   │
                   └── Synthesis


GitHub is used for version control. Remote synchronization is handled directly through SSH/rsync.