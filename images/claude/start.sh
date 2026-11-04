#!/bin/bash
set -euo pipefail
export HOME=/home/node
export SHELL=/bin/bash
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
cd "$HOME"
mkdir -p "$HOME/work" "$HOME/.claude"

# CLAUDE_CONFIG_DIR is in memory: logins and tokens never reach the PVC.
# Only these non-secret parts link to the PVC.
mkdir -p "$CLAUDE_CONFIG_DIR"
for name in projects settings.json CLAUDE.md keybindings.json agents skills plugins; do
  ln -sfn "$HOME/.claude/$name" "$CLAUDE_CONFIG_DIR/$name"
done
mkdir -p "$HOME/.claude/projects"

# PID 1 supervises the daemon and reaps orphaned processes.
set +e
cd "$HOME/work"
dpid=
while true; do
  if [ -z "$dpid" ] || ! kill -0 "$dpid" 2>/dev/null; then
    claude daemon run &
    dpid=$!
  fi
  sleep 10 & wait $!
done
