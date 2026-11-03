#!/usr/bin/env bash
# Runs in the remote pod, sent by beam-start.sh.
#
# Reads a gzipped tar of the local .claude settings, CLAUDE.md, agents,
# skills and plugins on stdin, extracts it onto the PVC, and drops the hooks.
set -euo pipefail

tar -xz -C /home/node
node -e '
  const fs = require("fs");
  const p = "/home/node/.claude/settings.json";
  const s = JSON.parse(fs.readFileSync(p, "utf8"));
  delete s.hooks;
  fs.writeFileSync(p, JSON.stringify(s, null, 2) + "\n");
'
