#!/usr/bin/env bash
# Runs in the remote pod, sent by beam-copy.sh.
#
# Usage: beam-remote-resume.sh SESSION_ID [COLORTERM]
#
# Reads a gzipped tar of a session transcript on stdin. Stops the background
# session with this ID, installs the transcript, and resumes it as a
# background session. The session renders with the given COLORTERM.
set -euo pipefail

id=$1
colorterm=${2:-}
CLAUDE=/home/node/.local/bin/claude
PROJECT=/home/node/.claude/projects/-home-node-work

"$CLAUDE" stop "${id:0:8}" >/dev/null 2>&1 || true
mkdir -p "$PROJECT"
tar -xz -C "$PROJECT"
cd /home/node/work
COLORTERM=$colorterm "$CLAUDE" --bg --resume "$id" >/dev/null
