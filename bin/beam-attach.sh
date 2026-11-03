#!/usr/bin/env bash
# Attach to a remote Claude Code background session, in the current kube context.
#
# Usage: beam-attach.sh [ID]
#
# With ID, opens that session. Without ID, opens agent view to pick one.
# Detach: Ctrl+Z. The session keeps running.
set -euo pipefail

NS=claude-theo
POD=claude-0
CLAUDE=/home/node/.local/bin/claude

# Attach clients left behind by dropped connections.
kubectl -n "$NS" exec "$POD" -c claude -- pkill -f "^$CLAUDE attach " || true

if [ -n "${1:-}" ]; then
  cmd=(attach "$1")
else
  cmd=(agents)
fi

kubectl -n "$NS" exec -it "$POD" -c claude -- \
  env TERM="${TERM:-xterm-256color}" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
  "$CLAUDE" "${cmd[@]}"
