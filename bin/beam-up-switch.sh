#!/usr/bin/env bash
# Run a Claude Code session in a new remote instance and switch this tmux pane to it.
#
# Usage: beam-up-switch.sh [-n INSTANCE] [--persistent] [--new | SESSION_ID]
#
# Run it with `! bin/beam-up-switch.sh` inside Claude Code, in tmux:
#   1. Creates the instance and starts the session with beam-up.sh.
#   2. Replaces this pane's local Claude with beam-attach.sh.
# The local Claude is killed. Detach with Ctrl+Z: the pane drops to a shell.
set -euo pipefail

BIN="$(dirname "$(readlink -f "$0")")"

if [ -z "${TMUX_PANE:-}" ]; then
  echo "Not in tmux: run this from a Claude Code session inside tmux" >&2
  exit 1
fi

# The last line of beam-up.sh is "Attach with: bin/beam-attach.sh INSTANCE SHORT".
last=$("$BIN/beam-up.sh" "$@" | tee /dev/stderr | tail -n 1)
read -r _ _ _ instance short <<<"$last"

tmux respawn-pane -k -t "$TMUX_PANE" -c "$PWD" "$BIN/beam-attach.sh $instance $short; exec $SHELL"
