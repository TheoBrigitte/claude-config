#!/usr/bin/env bash
# Create a remote instance and run a Claude Code background session in it, in
# the current kube context.
#
# Usage: beam-up.sh [-n INSTANCE] [--persistent] [--new | SESSION_ID]
#
# Without SESSION_ID, copies the session this runs from: run it with
# `! bin/beam-up.sh` inside Claude Code. The local session keeps running.
# The remote copy is a fork from this point on. With --new, starts an empty
# session instead.
#
# An instance is the namespace claude-theo-INSTANCE with one pod. INSTANCE
# defaults to the session's short ID. Every run creates a new instance, with
# the local settings and the current local login. The login goes into the
# pod's memory only. --persistent puts the home volume on a 20Gi gp3 PVC.
#
# Runs beam-remote-copy.sh in the pod, in one exec.
set -euo pipefail

BIN="$(dirname "$(readlink -f "$0")")"
MANIFESTS="$BIN/../k8s/claude-graveler/manifests.yaml"
POD=claude-0
# shellcheck source=beam-lib.sh
. "$BIN/beam-lib.sh"
USAGE="Usage: beam-up.sh [-n INSTANCE] [--persistent] [--new | SESSION_ID]"

# Each step shows while it runs, then gets a green check when done.
# beam-up-switch.sh pipes stdout through tee to stderr, hence the -t 2.
if [ -t 1 ] || [ -t 2 ]; then
  step() { label=$1; printf '\033[2m○ %s\033[0m' "$label"; }
  ok() { printf '\r\033[K\033[32m✔\033[0m %s\n' "${1:-$label}"; }
  next=$'\033[36m➜\033[0m'
else
  step() { label=$1; }
  ok() { printf '✔ %s\n' "${1:-$label}"; }
  next='➜'
fi

instance='' new='' persistent=''
while [ $# -gt 0 ]; do
  case $1 in
    -n) instance=${2:?$USAGE}; shift 2 ;;
    --new) new=1; shift ;;
    --persistent) persistent=1; shift ;;
    -*) echo "$USAGE" >&2; exit 1 ;;
    *) break ;;
  esac
done

if [ -n "$new" ]; then
  if [ $# -gt 0 ]; then
    echo "--new and SESSION_ID are mutually exclusive" >&2
    exit 1
  fi
  # The UUID names the instance only: --bg picks the session ID.
  id=$(cat /proc/sys/kernel/random/uuid)
else
  id="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
  if [ -z "$id" ]; then
    echo "No session ID: pass one, or run this from Claude Code with !" >&2
    exit 1
  fi
fi
instance="${instance:-${id:0:8}}"
if ! [[ $instance =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "Invalid instance name: $instance" >&2
  exit 1
fi
NS="claude-theo-$instance"

if kubectl get ns "$NS" >/dev/null 2>&1; then
  echo "Instance $instance exists: destroy it with bin/beam-destroy.sh $instance, or pick another -n" >&2
  exit 1
fi

snap=$(mktemp -d)
trap 'rm -rf "$snap"' EXIT
snapped=()
mode=new
if [ -z "$new" ]; then
  mode=resume
  step "Snapshot session $id"
  transcript=$(find "$HOME"/.claude/projects/ -maxdepth 2 -name "$id.jsonl" -print -quit)
  if [ -z "$transcript" ]; then
    echo "No transcript for session $id" >&2
    exit 1
  fi
  dir=$(dirname "$transcript")
  cp "$transcript" "$snap/$id.jsonl"
  [ "$(tail -c 1 "$snap/$id.jsonl")" = "" ] || sed -i '$d' "$snap/$id.jsonl"
  snapped=(--transform "s,^$id,home/node/.beam/$id,S" -C "$snap" "$id.jsonl")
  if [ -d "$dir/$id" ]; then
    cp -r "$dir/$id" "$snap/"
    snapped+=("$id")
  fi
  ok
fi

step "Create instance $instance"
render=("s/INSTANCE/$instance/g")
if [ -n "$persistent" ]; then
  render+=('/# ephemeral$/d' 's/^#persistent //')
fi
sed "${render[@]/#/-e}" "$MANIFESTS" | kubectl apply -f - >/dev/null
ok

step "Start pod"
until kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=300s >/dev/null 2>&1; do
  sleep 2
done
ok

step "Push login and settings, start session"
# The pod prints the session's short ID.
short=$(beam_tar "${snapped[@]}" |
  kubectl -n "$NS" exec -i "$POD" -c claude -- \
    bash -c "$(cat "$BIN/beam-remote-copy.sh")" beam-remote-copy.sh "$mode" "$id" "${COLORTERM:-}")

ok "Started session $short in instance $instance"
echo "$next Attach with: bin/beam-attach.sh $instance $short"
