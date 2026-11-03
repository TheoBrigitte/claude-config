#!/usr/bin/env bash
# Runs in the remote pod, sent by beam-up.sh.
#
# Usage: beam-remote-copy.sh SESSION_ID [COLORTERM]
#
# Reads a tar on stdin and extracts it at /. Its members carry their
# destination paths:
#   run/claude/config/.claude.json.new, .credentials.json.new: the login,
#     on the memory volume only.
#   home/node/.claude/...: the settings, on a new instance only.
#   home/node/.beam/<id>.jsonl and <id>/: the transcript, staged on the PVC.
# Installs the login with ~/work trusted, drops the hooks from the settings,
# waits for Claude and its daemon, stops the background session with this
# ID, installs the transcript, and resumes it as a background session.
set -euo pipefail
umask 077

id=$1
colorterm=${2:-}
CONFIG=/run/claude/config
CLAUDE=/home/node/.local/bin/claude
STAGE=/home/node/.beam
PROJECT=/home/node/.claude/projects/-home-node-work

rm -rf "$STAGE"
tar -xz -C /

node -e '
  const fs = require("fs");
  const p = process.argv[1];
  const c = JSON.parse(fs.readFileSync(p, "utf8"));
  c.projects = c.projects || {};
  c.projects["/home/node/work"] = { ...c.projects["/home/node/work"], hasTrustDialogAccepted: true };
  fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n");
' "$CONFIG/.claude.json.new"
mv "$CONFIG/.claude.json.new" "$CONFIG/.claude.json"
mv "$CONFIG/.credentials.json.new" "$CONFIG/.credentials.json"

node -e '
  const fs = require("fs");
  const p = "/home/node/.claude/settings.json";
  const s = JSON.parse(fs.readFileSync(p, "utf8"));
  if (s.hooks) {
    delete s.hooks;
    fs.writeFileSync(p, JSON.stringify(s, null, 2) + "\n");
  }
'

until [ -x "$CLAUDE" ]; do sleep 2; done
until "$CLAUDE" daemon status >/dev/null 2>&1; do sleep 1; done

"$CLAUDE" stop "${id:0:8}" >/dev/null 2>&1 || true
# The stop returns before the session exits. A resume before then forks it.
for _ in $(seq 50); do
  grep -qs "\"${id:0:8}\": {" "$CONFIG/daemon/roster.json" || break
  sleep 0.2
done
mkdir -p "$PROJECT"
rm -rf "${PROJECT:?}/$id"
mv "$STAGE"/* "$PROJECT/"
rmdir "$STAGE"
cd /home/node/work
COLORTERM=$colorterm "$CLAUDE" --bg --resume "$id" >/dev/null
