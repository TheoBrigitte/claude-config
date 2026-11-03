#!/usr/bin/env bash
# Copy a Claude Code session to the remote pod and switch this tmux pane to it.
#
# Usage: beam-copy-switch.sh [SESSION_ID]
#
# Run it with `! bin/beam-copy-switch.sh` inside Claude Code, in tmux:
#   1. Copies and resumes the session in the pod with beam-copy.sh.
#   2. Replaces this pane's local Claude with beam-attach.sh.
# The local Claude is killed. Detach with Ctrl+Z: the pane drops to a shell.
set -euo pipefail

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

"$BIN/beam-copy.sh" "$id"

tmux respawn-pane -k -t "$TMUX_PANE" -c "$PWD" "$BIN/beam-attach.sh $short; exec $SHELL"
