#!/usr/bin/env bash
# Copy a Claude Code session to a remote instance and switch this tmux pane to it.
#
# Usage: beam-up-switch.sh [-n INSTANCE] [SESSION_ID]
#
# Run it with `! bin/beam-up-switch.sh` inside Claude Code, in tmux:
#   1. Copies and resumes the session in the instance with beam-up.sh.
#   2. Replaces this pane's local Claude with beam-attach.sh.
# The local Claude is killed. Detach with Ctrl+Z: the pane drops to a shell.
set -euo pipefail

BIN="$(dirname "$(readlink -f "$0")")"

if [ -z "${TMUX_PANE:-}" ]; then
  echo "Not in tmux: run this from a Claude Code session inside tmux" >&2
  exit 1
fi

instance=
while getopts n: opt; do
  case $opt in
    n) instance=$OPTARG ;;
    *) exit 1 ;;
  esac
done
shift $((OPTIND - 1))

id="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -z "$id" ]; then
  echo "No session ID: pass one, or run this from Claude Code with !" >&2
  exit 1
fi
short="${id:0:8}"
instance="${instance:-$short}"

"$BIN/beam-up.sh" -n "$instance" "$id"

tmux respawn-pane -k -t "$TMUX_PANE" -c "$PWD" "$BIN/beam-attach.sh $instance $short; exec $SHELL"
