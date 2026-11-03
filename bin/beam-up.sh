#!/usr/bin/env bash
# Copy a Claude Code session to a remote instance and resume it there, in the
# current kube context.
#
# Usage: beam-up.sh [-n INSTANCE] [SESSION_ID]
#
# Without SESSION_ID, copies the session this runs from: run it with
# `! bin/beam-up.sh` inside Claude Code. The local session keeps running.
# The remote copy is a fork from this point on.
#
# An instance is the namespace claude-theo-INSTANCE with one pod. INSTANCE
# defaults to the session's short ID. A missing instance is created, with the
# local settings. An existing one gets the session copied again.
#
# Every run pushes the current local login into the pod's memory. Runs
# beam-remote-copy.sh in the pod, in one exec.
set -euo pipefail

BIN="$(dirname "$(readlink -f "$0")")"
MANIFESTS="$BIN/../k8s/claude-graveler/manifests.yaml"
POD=claude-0

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
if ! [[ $instance =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "Invalid instance name: $instance" >&2
  exit 1
fi
NS="claude-theo-$instance"

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

settings=()
if ! kubectl get ns "$NS" >/dev/null 2>&1; then
  echo "Creating instance $instance"
  sed "s/INSTANCE/$instance/g" "$MANIFESTS" | kubectl apply -f - >/dev/null
  until kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=300s >/dev/null 2>&1; do
    sleep 2
  done
  settings=(-C "$HOME" .claude/settings.json .claude/CLAUDE.md .claude/keybindings.json
    .claude/agents .claude/skills .claude/plugins)
fi

# Each member is renamed to its destination path in the pod.
tar -cz \
  --transform 's,^\.claude\.json$,run/claude/config/.claude.json.new,S' \
  --transform 's,^\.credentials\.json$,run/claude/config/.credentials.json.new,S' \
  --transform 's,^\.claude/,home/node/.claude/,S' \
  --transform "s,^$id,home/node/.beam/$id,S" \
  -C "$(dirname "$(readlink -f "$HOME/.claude.json")")" .claude.json \
  -C "$HOME/.claude" .credentials.json \
  "${settings[@]}" \
  -C "$snap" "${files[@]}" |
  kubectl -n "$NS" exec -i "$POD" -c claude -- \
    bash -c "$(cat "$BIN/beam-remote-copy.sh")" beam-remote-copy.sh "$id" "${COLORTERM:-}"

echo "Copied session $id to instance $instance and resumed it"
echo "Attach with: bin/beam-attach.sh $instance $short"
