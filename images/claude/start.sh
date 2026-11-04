#!/bin/bash
set -euo pipefail
mkdir -p "$HOME/work" "$HOME/.claude/projects" "$CLAUDE_CONFIG_DIR"

# CLAUDE_CONFIG_DIR is in memory: logins and tokens never reach the PVC.
# Only these non-secret parts link to the PVC.
for name in projects settings.json CLAUDE.md keybindings.json agents skills plugins; do
  ln -sfn "$HOME/.claude/$name" "$CLAUDE_CONFIG_DIR/$name"
done
cd "$HOME/work"
exec claude daemon run
