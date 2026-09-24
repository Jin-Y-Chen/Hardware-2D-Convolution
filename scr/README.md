From the repository in bash:

chmod +x scr/ssh_rsync

Then run:

./scr/ssh_rsync

Your workflow becomes:

Local Git repository
        │
        ├── edit src/
        │
        ├── ./scripts/ssh_rsync
        │          │
        │          │ SSH + rsync
        │          ▼
        │      eceap1
        │          │
        │          └── ~/myproject/src/
        │
        └── ./scripts/remote_test
                   │
                   ▼
             emulation
             compliance
             synthesis