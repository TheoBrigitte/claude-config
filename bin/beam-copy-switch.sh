#!/usr/bin/env bash
# Copy a Claude Code session to the remote pod and switch this tmux pane to it.
#
# Usage: beam-copy-switch.sh [SESSION_ID]
#
# Run it with `! bin/beam-copy-switch.sh` inside Claude Code, in tmux:
#   1. Copies the session with beam-copy.sh.
#   2. Restarts the remote tmux pane with `claude --resume`.
#   3. Replaces this pane's local Claude with beam-attach.sh.
# The local Claude and the remote pane's current process are killed.
# After detaching, the pane drops to a shell.
set -euo pipefail

NS=claude-theo
POD=claude-0
TMUX_BIN=/home/node/micromamba/envs/tools/bin/tmux
BIN="$(dirname "$(readlink -f "$0")")"

if [ -z "${TMUX_PANE:-}" ]; then
  echo "Not in tmux: run this from a Claude Code session inside tmux" >&2
  exit 1
fi

id="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -z "$id" ]; then
  echo "No session ID: pass one, or run this from Claude Code with !" >&2
  exit 1
fi
"$BIN/beam-copy.sh" "$id"

kubectl -n "$NS" exec "$POD" -c claude -- \
  "$TMUX_BIN" respawn-pane -k -t main -c /home/node/work \
  "/home/node/.local/bin/claude --resume $id; exec bash"

tmux respawn-pane -k -t "$TMUX_PANE" -c "$PWD" "$BIN/beam-attach.sh; exec $SHELL"
