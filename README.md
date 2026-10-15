# orcd-notes

Personal notes and helper scripts for working on MIT ORCD's Engaging cluster.

Official docs: <https://orcd-docs.mit.edu/>

## Contents

| Topic | Note | Scripts |
|-------|------|---------|
| VSCode on a compute node (auto-update SSH config) | [notes/vscode-compute-node.md](notes/vscode-compute-node.md) | [scripts/orcd_interactive.sh](scripts/orcd_interactive.sh), [scripts/orcd_node.sh](scripts/orcd_node.sh) |

## Quick start

```bash
git clone <this-repo>
cd orcd-notes
./scripts/orcd_interactive.sh     # get a node (1 core, 16 GB, 4 h) and update ~/.ssh/config
# keep that terminal open, then connect to the `orcd-compute` host from VSCode
# closing the terminal ends the allocation (no leftover jobs on the cluster)
```

Prerequisite: SSH key authentication to the cluster. See the note above.

## Conventions

- One markdown file per topic under `notes/`.
- Reusable scripts under `scripts/`, with usage documented in the header and in
  the matching note.

## Acknowledgements

Written with the help of [Claude](https://claude.com/claude-code).
