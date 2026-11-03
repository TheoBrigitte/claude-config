#!/usr/bin/env bash
# Attach to a remote Claude Code background session, in the current kube context.
#
# Usage: beam-attach.sh INSTANCE [ID]
#
# With ID, opens that session. Without ID, opens the session beam-up.sh
# started, else agent view to pick one.
# Detach: Ctrl+Z. The session keeps running.
set -euo pipefail

instance=${1:?Usage: beam-attach.sh INSTANCE [ID]}
cmd=()
if [ -n "${2:-}" ]; then
  cmd=(attach "$2")
fi

# One exec: kill the attach clients left behind by dropped connections, then
# attach. The ^ anchor keeps pkill off this sh's own command line.
# ~/.beam-session holds the short ID of the session beam-up.sh started.
# shellcheck disable=SC2016
kubectl -n "claude-theo-$instance" exec -it claude-0 -c claude -- sh -c '
  pkill -f "^/home/node/.local/bin/claude attach "
  t=$1 c=$2
  shift 2
  if [ $# -eq 0 ]; then
    if [ -s /home/node/.beam-session ]; then
      set -- attach "$(cat /home/node/.beam-session)"
    else
      set -- agents
    fi
  fi
  cd /home/node/work
  exec env TERM="$t" COLORTERM="$c" LANG=C.UTF-8 LC_ALL=C.UTF-8 /home/node/.local/bin/claude "$@"
' sh "${TERM:-xterm-256color}" "${COLORTERM:-}" "${cmd[@]}"
