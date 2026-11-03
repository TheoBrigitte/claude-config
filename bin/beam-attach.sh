#!/usr/bin/env bash
# Attach to a remote Claude Code background session, in the current kube context.
#
# Usage: beam-attach.sh [--push-credentials] INSTANCE [ID]
#
# With ID, opens that session. Without ID, opens the session beam-up.sh
# started, else agent view to pick one.
# --push-credentials first pushes the current local login and settings, as
# beam-up.sh does, and resumes the session if the daemon doesn't run it. Use
# it after a pod restart.
# Detach: Ctrl+Z. The session keeps running.
set -euo pipefail

BIN="$(dirname "$(readlink -f "$0")")"
USAGE="Usage: beam-attach.sh [--push-credentials] INSTANCE [ID]"

push=''
if [ "${1:-}" = --push-credentials ]; then
  push=1
  shift
fi
instance=${1:?$USAGE}
id=${2:-}
NS="claude-theo-$instance"

# beam-remote-copy.sh prints the session's short ID.
if [ -n "$push" ]; then
  # shellcheck source=beam-lib.sh
  . "$BIN/beam-lib.sh"
  # shellcheck disable=SC2119
  id=$(beam_tar |
    kubectl -n "$NS" exec -i claude-0 -c claude -- \
      bash -c "$(cat "$BIN/beam-remote-copy.sh")" beam-remote-copy.sh login "$id" "${COLORTERM:-}")
fi

cmd=()
if [ -n "$id" ]; then
  cmd=(attach "$id")
fi

# One exec: kill the attach clients left behind by dropped connections, then
# attach. The ^ anchor keeps pkill off this sh's own command line.
# ~/.beam-session holds the short ID of the session beam-up.sh started.
# shellcheck disable=SC2016
kubectl -n "$NS" exec -it claude-0 -c claude -- sh -c '
  pkill -f "^/usr/local/bin/claude attach "
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
  exec env TERM="$t" COLORTERM="$c" LANG=C.UTF-8 LC_ALL=C.UTF-8 /usr/local/bin/claude "$@"
' sh "${TERM:-xterm-256color}" "${COLORTERM:-}" "${cmd[@]}"
