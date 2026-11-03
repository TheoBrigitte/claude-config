#!/usr/bin/env bash
# Set up the remote Claude Code pod in the current kube context.
#
# Usage: beam-start.sh
#
# Steps, each safe to rerun:
#   1. Apply the namespace, ConfigMap and StatefulSet.
#   2. Wait for the pod to install Claude.
#   3. On first run only, copy the local settings, CLAUDE.md, agents, skills
#      and plugins to the PVC, and drop the hooks.
#   4. Push the current local login and .claude.json into the pod's memory,
#      and trust ~/work. They never touch the PVC.
#   5. Wait for the Claude daemon.
#
# Attach with bin/beam-attach.sh, or move a session with bin/beam-copy-switch.sh.

set -euo pipefail

NS=claude-theo
POD=claude-0
CLAUDE=/home/node/.local/bin/claude
CONFIG=/run/claude/config
MANIFESTS="$(dirname "$(readlink -f "$0")")/../k8s/claude-graveler/manifests.yaml"

k() { kubectl -n "$NS" "$@"; }
pod() { k exec "$POD" -c claude -- "$@"; }
podin() { k exec -i "$POD" -c claude -- "$@"; }

echo "Applying manifests"
kubectl apply -f "$MANIFESTS"

echo "Waiting for Claude in the pod"
until pod test -x "$CLAUDE" 2>/dev/null; do sleep 5; done

if ! pod test -f /home/node/.claude/settings.json 2>/dev/null; then
  echo "Copying the local settings to the PVC"
  tar -cz -C "$HOME" \
    .claude/settings.json .claude/CLAUDE.md .claude/keybindings.json \
    .claude/agents .claude/skills .claude/plugins |
    podin tar -xz -C /home/node
  pod node -e '
    const fs = require("fs");
    const p = "/home/node/.claude/settings.json";
    const s = JSON.parse(fs.readFileSync(p, "utf8"));
    delete s.hooks;
    fs.writeFileSync(p, JSON.stringify(s, null, 2) + "\n");
  '
fi

echo "Pushing the local login into the pod's memory"
podin sh -c "umask 077 && cat > $CONFIG/.claude.json.tmp" < "$(readlink -f "$HOME/.claude.json")"
pod node -e '
  const fs = require("fs");
  const p = process.argv[1];
  const c = JSON.parse(fs.readFileSync(p, "utf8"));
  c.projects = c.projects || {};
  c.projects["/home/node/work"] = { ...c.projects["/home/node/work"], hasTrustDialogAccepted: true };
  fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n");
' "$CONFIG/.claude.json.tmp"
pod mv "$CONFIG/.claude.json.tmp" "$CONFIG/.claude.json"
podin sh -c "umask 077 && cat > $CONFIG/.credentials.json.tmp && mv $CONFIG/.credentials.json.tmp $CONFIG/.credentials.json" \
  < "$HOME/.claude/.credentials.json"

echo "Waiting for the Claude daemon"
until pod "$CLAUDE" daemon status >/dev/null 2>&1; do sleep 2; done

echo "Claude is running in $POD"
