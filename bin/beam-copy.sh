#!/usr/bin/env bash
# Copy a Claude Code session to the remote pod and resume it there, in the
# current kube context.
#
# Usage: beam-copy.sh [SESSION_ID]
#
# Without SESSION_ID, copies the session this runs from: run it with
# `! bin/beam-copy.sh` inside Claude Code. The local session keeps running.
# The remote copy is a fork from this point on.
#
# Stops the remote background session with this ID, if one runs, copies the
# transcript, and resumes it as a remote background session.
set -euo pipefail

NS=claude-theo
POD=claude-0
CLAUDE=/home/node/.local/bin/claude
REMOTE_PROJECT=/home/node/.claude/projects/-home-node-work

id="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -z "$id" ]; then
  echo "No session ID: pass one, or run this from Claude Code with !" >&2
  exit 1
fi
short="${id:0:8}"

transcript=$(find "$HOME"/.claude/projects/ -maxdepth 2 -name "$id.jsonl" -print -quit)
if [ -z "$transcript" ]; then
  echo "No transcript for session $id" >&2
  exit 1
fi
dir=$(dirname "$transcript")

snap=$(mktemp -d)
trap 'rm -rf "$snap"' EXIT
cp "$transcript" "$snap/$id.jsonl"
[ "$(tail -c 1 "$snap/$id.jsonl")" = "" ] || sed -i '$d' "$snap/$id.jsonl"
files=("$id.jsonl")
if [ -d "$dir/$id" ]; then
  cp -r "$dir/$id" "$snap/"
  files+=("$id")
fi

pod() { kubectl -n "$NS" exec "$POD" -c claude -- "$@"; }

pod "$CLAUDE" stop "$short" >/dev/null 2>&1 || true

tar -cz -C "$snap" "${files[@]}" |
  kubectl -n "$NS" exec -i "$POD" -c claude -- \
    sh -c "mkdir -p $REMOTE_PROJECT && tar -xz -C $REMOTE_PROJECT"

pod sh -c "cd /home/node/work && $CLAUDE --bg --resume $id" >/dev/null

echo "Copied session $id to $POD and resumed it"
echo "Attach with: bin/beam-attach.sh $short"
