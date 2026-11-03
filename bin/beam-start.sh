#!/usr/bin/env bash
# Set up the remote Claude Code pod in the current kube context.
#
# Usage: beam-start.sh
#
# Steps, each safe to rerun:
#   1. Apply the namespace, ConfigMap and StatefulSet.
#   2. Wait for the pod to install tmux and Claude and start the tmux session.
#   3. On first run only, copy the local Claude login and settings into the
#      pod, drop the hooks, trust ~/work, and restart Claude to load them.
#
# Attach with bin/beam-attach.sh.

set -euo pipefail

NS=claude-theo
POD=claude-0
TMUX=/home/node/micromamba/envs/tools/bin/tmux
MANIFESTS="$(dirname "$(readlink -f "$0")")/../k8s/claude-graveler/manifests.yaml"

k() { kubectl -n "$NS" "$@"; }
pod() { k exec "$POD" -c claude -- "$@"; }

echo "Applying manifests"
kubectl apply -f "$MANIFESTS"

echo "Waiting for the tmux session"
until pod "$TMUX" has-session -t main 2>/dev/null; do sleep 5; done

if ! pod test -f /home/node/.claude/.credentials.json; then
  echo "Copying the local Claude login and settings"
  tar -cz \
    -C "$(dirname "$(readlink -f "$HOME/.claude.json")")" .claude.json \
    -C "$HOME" \
    .claude/.credentials.json .claude/settings.json .claude/CLAUDE.md \
    .claude/keybindings.json .claude/statusline-command.sh .claude/voices \
    .claude/agents .claude/skills .claude/plugins |
    k exec -i "$POD" -c claude -- tar -xz -C /home/node

  pod node -e '
    const fs = require("fs");
    const settings = "/home/node/.claude/settings.json";
    const s = JSON.parse(fs.readFileSync(settings, "utf8"));
    delete s.hooks;
    s.permissions.allow = s.permissions.allow.filter(r => r !== "Glob(*)");
    fs.writeFileSync(settings, JSON.stringify(s, null, 2) + "\n");

    const state = "/home/node/.claude.json";
    const c = JSON.parse(fs.readFileSync(state, "utf8"));
    c.projects = c.projects || {};
    c.projects["/home/node/work"] = { ...c.projects["/home/node/work"], hasTrustDialogAccepted: true };
    fs.writeFileSync(state, JSON.stringify(c, null, 2) + "\n");
  '

  echo "Restarting Claude with the copied settings"
  pod "$TMUX" kill-session -t main
  until pod "$TMUX" has-session -t main 2>/dev/null; do sleep 2; done
fi

echo "Claude is running in $POD"
