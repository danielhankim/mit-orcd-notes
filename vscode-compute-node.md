# VSCode on an ORCD (Engaging) compute node, automated

Reference: [ORCD docs: VSCode Remote SSH](https://orcd-docs.mit.edu/recipes/vscode/)

## The problem

Running VSCode Remote SSH on a login node is discouraged. The recommended
workflow is to run it on a compute node, which needs three manual steps every
session:

1. `salloc -t HH:MM:SS -p mit_normal` to get an interactive allocation
2. `hostname` (or `squeue --me`) to find the node name
3. Edit `HostName` in the `orcd-compute` block of `~/.ssh/config`, then connect

`scripts/orcd_node.sh` does all of this with one command, run from your
**local machine**.

## Prerequisite: SSH key (this is the part that bit me)

Connecting to a compute node through `ProxyJump` requires **SSH key
authentication**. The ORCD docs say this explicitly: an SSH key is required to
use VSCode on a compute node. Setup guide:
<https://orcd-docs.mit.edu/accessing-orcd/ssh-setup/>

Checklist:

- [ ] Key pair exists locally (e.g. `~/.ssh/id_ed25519` and `.pub`)
- [ ] Public key is installed on the cluster (`~/.ssh/authorized_keys`)
- [ ] `ssh orcd-login` works
- [ ] `ssh orcd-compute` works once the node name is filled in
- [ ] Permissions are sane: `chmod 700 ~/.ssh`, `chmod 600 ~/.ssh/authorized_keys`

> TODO: write down what exactly was wrong with my key setup so I don't repeat it.

If the script's `salloc`/`squeue` step or the final connection fails, check the
key setup first, before debugging the script.

## SSH config

Local `~/.ssh/config` (the script only rewrites `HostName` in the
`orcd-compute` block):

```
Host orcd-login
  HostName orcd-login.mit.edu
  ControlMaster auto
  ControlPath ~/.ssh/%r@%h:%p
  ControlPersist 300s
  User USERNAME

Host orcd-compute
  User USERNAME
  HostName nodename
  ProxyJump orcd-login
```

The `ControlMaster` lines keep the number of Duo prompts down by reusing one
authenticated connection to the login node.

## Script A: `scripts/orcd_node.sh` (recommended)

```bash
./scripts/orcd_node.sh 4     # request 4 hours
./scripts/orcd_node.sh -1    # no time flag (partition default)
```

How it works:

1. SSHes to `orcd-login` and runs `salloc --no-shell -J vscode -p mit_normal [-t H:00:00]`.
2. `--no-shell` holds the allocation without an interactive shell, so it
   survives after the SSH call returns.
3. Reads the job ID from "Granted job allocation", then the node from
   `squeue -h -j <jid> -o %N`.
4. Rewrites `HostName` in the `orcd-compute` block (backup saved as
   `~/.ssh/config.bak`).

Release the node when finished: `ssh orcd-login scancel -n vscode`

## Script B: `scripts/orcd_interactive.sh` (keeps a shell)

Use this if you want the classic interactive `salloc` shell in your terminal.
A background watcher reuses the same SSH connection to poll `squeue` and update
the config as soon as the job is running. Exiting the shell ends the
allocation.

```bash
./scripts/orcd_interactive.sh 2
```

## Notes and gotchas

- Run the scripts **locally**, not on the cluster. They need to SSH out and
  edit the local `~/.ssh/config`.
- Time argument is in **hours**; `-1` omits `-t`. For minutes, change
  `-t ${HOURS}:00:00` to `-t ${HOURS}`.
- Both scripts assume the host aliases `orcd-login` and `orcd-compute`.
  Change the variables at the top if yours differ.
- On Windows, run in WSL or Git Bash and make sure `CONFIG` points at the
  `~/.ssh/config` that VSCode actually reads.
- Cancel stale jobs (`scancel -n vscode`) before starting a new one, since the
  scripts identify the job by name.
- Only add the directories you need to the VSCode workspace, not your whole
  home or group storage.

## VSCode settings that avoid Duo lockouts

From the ORCD docs:

- `Remote.SSH: Connect Timeout` = 60
- `Remote.SSH: Max Reconnection Attempts` = 0 (or 1)
