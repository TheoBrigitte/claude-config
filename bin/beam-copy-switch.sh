#!/usr/bin/env bash
# Copy a Claude Code session to the remote pod and switch this tmux pane to it.
#
# Usage: beam-copy-switch.sh [SESSION_ID]
#
# Run it with `! bin/beam-copy-switch.sh` inside Claude Code, in tmux:
#   1. Stops the remote background session with this ID, if one runs.
#   2. Copies the session with beam-copy.sh.
#   3. Resumes it as a remote background session.
#   4. Replaces this pane's local Claude with beam-attach.sh.
# The local Claude is killed. Detach with Ctrl+Z: the pane drops to a shell.
set -euo pipefail

NS=claude-theo
POD=claude-0
CLAUDE=/home/node/.local/bin/claude
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
short="${id:0:8}"

pod() { kubectl -n "$NS" exec "$POD" -c claude -- "$@"; }

pod "$CLAUDE" stop "$short" >/dev/null 2>&1 || true
"$BIN/beam-copy.sh" "$id"
pod sh -c "cd /home/node/work && $CLAUDE --bg --resume $id"

tmux respawn-pane -k -t "$TMUX_PANE" -c "$PWD" "$BIN/beam-attach.sh $short; exec $SHELL"
