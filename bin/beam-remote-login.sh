#!/usr/bin/env bash
# Runs in the remote pod, sent by beam-start.sh.
#
# Reads a tar of .claude.json and .credentials.json on stdin and installs
# them into the pod's memory, with ~/work trusted. Waits for Claude and its
# daemon. Prints "settings: missing" when the PVC has no settings yet.
set -euo pipefail
umask 077

CONFIG=/run/claude/config
CLAUDE=/home/node/.local/bin/claude

mkdir -p "$CONFIG"
t=$(mktemp -d /run/claude/push.XXXXXX)
trap 'rm -rf "$t"' EXIT
tar -x -C "$t"
node -e '
  const fs = require("fs");
  const p = process.argv[1];
  const c = JSON.parse(fs.readFileSync(p, "utf8"));
  c.projects = c.projects || {};
  c.projects["/home/node/work"] = { ...c.projects["/home/node/work"], hasTrustDialogAccepted: true };
  fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n");
' "$t/.claude.json"
mv "$t/.claude.json" "$CONFIG/.claude.json"
mv "$t/.credentials.json" "$CONFIG/.credentials.json"

until [ -x "$CLAUDE" ]; do sleep 2; done
until "$CLAUDE" daemon status >/dev/null 2>&1; do sleep 1; done

[ -f /home/node/.claude/settings.json ] || echo "settings: missing"
