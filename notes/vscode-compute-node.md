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

What was actually wrong for me: no SSH key was set up on Engaging at all, so
the hop from `orcd-login` to the compute node fell back to password auth and
got "permission denied" instead of a password prompt. See
[Troubleshooting](#troubleshooting) below.

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

What each line does:

- **`Host orcd-login`** — the alias you type (`ssh orcd-login`); everything
  indented under it applies only to connections using this alias.
- **`HostName orcd-login.mit.edu`** — the actual address to connect to.
- **`ControlMaster auto`** — enables SSH connection multiplexing: the first
  connection becomes a "master" and later connections reuse it instead of a
  fresh handshake.
- **`ControlPath ~/.ssh/%r@%h:%p`** — where the multiplexing socket file
  lives (`%r`/`%h`/`%p` = remote user/host/port).
- **`ControlPersist 300s`** — keeps the master connection (and its auth)
  alive in the background for 300s after your last session closes, so a
  reconnect within that window skips Duo/MFA. This is what lets
  `orcd_interactive.sh`'s watcher reuse the already-authenticated
  `orcd-login` connection.
- **`User USERNAME`** — your cluster account name; replace the placeholder.
- **`Host orcd-compute`** — the alias VSCode and both scripts connect to.
- **`HostName nodename`** — placeholder; the scripts overwrite this with the
  real compute node name once `salloc`/`squeue` reports it.
- **`ProxyJump orcd-login`** — hop through `orcd-login` first (reusing its
  multiplexed connection) since the compute node usually isn't reachable
  directly from outside the cluster network.

The `ControlMaster`/`ControlPersist` lines keep the number of Duo prompts down
by reusing one authenticated connection to the login node.

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

## Troubleshooting

### "Permission denied" connecting to the compute node

Symptom: VS Code Remote-SSH (or a plain `ssh orcd-compute`) prompts for a
password when hopping from `orcd-login` to the compute node, then fails with
`Permission denied`.

Per the [ORCD FAQ](https://orcd-docs.mit.edu/faqs/#i-cannot-connect-to-a-compute-node-using-vs-code-remote-ssh):

> Sometimes, when following our instructions for running VS Code on the
> cluster, users are prompted to enter their password when they connect to
> the compute node and they get "permission denied." This is most often
> because they do not have an SSH key set up on Engaging.

Fix: set up an SSH key following the
[ORCD SSH setup guide](https://orcd-docs.mit.edu/accessing-orcd/ssh-setup/)
(same as the [Prerequisite](#prerequisite-ssh-key-this-is-the-part-that-bit-me)
checklist above). Once a key is installed, the compute node hop authenticates
with it directly instead of falling back to a password prompt that then gets
rejected.

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
