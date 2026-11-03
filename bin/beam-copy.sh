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
# Runs beam-start.sh, so the pod has the current local login. Then runs
# beam-remote-resume.sh in the pod: it stops the remote background session
# with this ID, if one runs, installs the transcript, and resumes it as a
# remote background session.
set -euo pipefail

NS=claude-theo
POD=claude-0
BIN="$(dirname "$(readlink -f "$0")")"

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

"$BIN/beam-start.sh" >/dev/null

tar -cz -C "$snap" "${files[@]}" |
  kubectl -n "$NS" exec -i "$POD" -c claude -- \
    bash -c "$(cat "$BIN/beam-remote-resume.sh")" beam-remote-resume.sh "$id" "${COLORTERM:-}"

echo "Copied session $id to $POD and resumed it"
echo "Attach with: bin/beam-attach.sh $short"
