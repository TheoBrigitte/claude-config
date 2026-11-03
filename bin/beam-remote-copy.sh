#!/usr/bin/env bash
# Runs in the remote pod, sent by beam-up.sh.
#
# Usage: beam-remote-copy.sh new|resume SESSION_ID [COLORTERM]
#
# SESSION_ID is ignored with new.
#
# Reads a tar on stdin and extracts it at /. Its members carry their
# destination paths:
#   run/claude/config/.claude.json.new, .credentials.json.new: the login,
#     on the memory volume only.
#   home/node/.claude/...: the settings.
#   home/node/.beam/<id>.jsonl and <id>/: the transcript, staged on the home
#     volume, resume only.
# Installs the login with ~/work trusted, drops the hooks from the settings
# and waits for Claude and its daemon. Then starts an empty background session
# (new), or installs the transcript and resumes it as a background session
# (resume). Writes the session's short ID to ~/.beam-session for
# beam-attach.sh, and prints it.
set -euo pipefail
umask 077

mode=$1
id=$2
colorterm=${3:-}
CONFIG=/run/claude/config
CLAUDE=/home/node/.local/bin/claude
STAGE=/home/node/.beam
PROJECT=/home/node/.claude/projects/-home-node-work

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

cd /home/node/work
if [ "$mode" = new ]; then
  # --bg picks its own session ID: it ignores --session-id.
  out=$(COLORTERM=$colorterm "$CLAUDE" --bg)
  short=$(sed -n 's/^backgrounded · \([0-9a-f]\{8\}\).*/\1/p' <<<"$out")
  [ -n "$short" ] || { echo "$out" >&2; exit 1; }
else
  mkdir -p "$PROJECT"
  mv "$STAGE"/* "$PROJECT/"
  rmdir "$STAGE"
  COLORTERM=$colorterm "$CLAUDE" --bg --resume "$id" >/dev/null
  short=${id:0:8}
fi
echo "$short" >/home/node/.beam-session
echo "$short"
