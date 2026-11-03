#!/usr/bin/env bash
# Copy a Claude Code session to the remote pod, in the current kube context.
#
# Usage: beam-copy.sh [SESSION_ID]
#
# Without SESSION_ID, copies the session this runs from: run it with
# `! bin/beam-copy.sh` inside Claude Code. The local session keeps running.
# The remote copy is a fork from this point on.
set -euo pipefail

NS=claude-theo
POD=claude-0
REMOTE_PROJECT=/home/node/.claude/projects/-home-node-work

id="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -z "$id" ]; then
  echo "No session ID: pass one, or run this from Claude Code with !" >&2
  exit 1
fi

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

tar -cz -C "$snap" "${files[@]}" |
  kubectl -n "$NS" exec -i "$POD" -c claude -- \
    sh -c "mkdir -p $REMOTE_PROJECT && tar -xz -C $REMOTE_PROJECT"

echo "Copied session $id to $POD"
echo "Resume it in the pod with: claude --bg --resume $id"
