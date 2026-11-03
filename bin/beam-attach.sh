#!/usr/bin/env bash
# Attach to the remote Claude Code tmux session, in the current kube context.
# tmux prefix in the pod is Ctrl+A. Detach: Ctrl+A d.
set -euo pipefail

NS=claude-theo
POD=claude-0

kubectl -n "$NS" exec -it "$POD" -c claude -- \
  env TERM="${TERM:-xterm-256color}" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
  /home/node/micromamba/envs/tools/bin/tmux attach -t main
