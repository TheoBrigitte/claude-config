#!/usr/bin/env bash
# Set up the remote Claude Code pod in the current kube context.
#
# Usage: beam-start.sh
#
# Steps, each safe to rerun:
#   1. Apply the namespace, ConfigMap and StatefulSet.
#   2. Wait for the pod.
#   3. Push the current local login and .claude.json into the pod's memory,
#      and trust ~/work. They never touch the PVC. Wait for Claude and its
#      daemon. Runs beam-remote-login.sh in the pod.
#   4. On first run only, copy the local settings, CLAUDE.md, agents, skills
#      and plugins to the PVC, and drop the hooks. Runs
#      beam-remote-settings.sh in the pod.
#
# Attach with bin/beam-attach.sh, or move a session with bin/beam-copy.sh.

set -euo pipefail

NS=claude-theo
POD=claude-0
BIN="$(dirname "$(readlink -f "$0")")"
MANIFESTS="$BIN/../k8s/claude-graveler/manifests.yaml"

remote() {
  local script=$1
  shift
  kubectl -n "$NS" exec -i "$POD" -c claude -- bash -c "$(cat "$BIN/$script")" "$script" "$@"
}

echo "Applying manifests"
kubectl apply -f "$MANIFESTS"

echo "Waiting for the pod"
until kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=300s >/dev/null 2>&1; do
  sleep 2
done

echo "Pushing the local login into the pod's memory"
state=$(
  tar -c \
    -C "$(dirname "$(readlink -f "$HOME/.claude.json")")" .claude.json \
    -C "$HOME/.claude" .credentials.json |
    remote beam-remote-login.sh
)

if [ "$state" = "settings: missing" ]; then
  echo "Copying the local settings to the PVC"
  tar -cz -C "$HOME" \
    .claude/settings.json .claude/CLAUDE.md .claude/keybindings.json \
    .claude/agents .claude/skills .claude/plugins |
    remote beam-remote-settings.sh
fi

echo "Claude is running in $POD"
