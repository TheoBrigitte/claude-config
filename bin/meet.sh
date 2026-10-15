#!/usr/bin/env bash
# Bring Claude into a Google Meet call: audio devices, camera, face and voice loop.
#
# Usage: meet.sh [MEET_URL]
#
# Opens MEET_URL in Chrome for Claude's tab. Ctrl+C stops everything.
set -euo pipefail

bin=$(dirname "$(readlink -f "$0")")

[[ -e /dev/video10 ]] ||
  sudo modprobe v4l2loopback video_nr=10 card_label=Claude exclusive_caps=1
"$bin/meet-audio.sh" up

"$bin/meet-face.py" &
face=$!
trap 'kill $face 2>/dev/null; "$bin/meet-audio.sh" down' EXIT

if [[ -n ${1:-} ]]; then
  google-chrome-stable "$1" >/dev/null 2>&1
fi
cat >&2 <<'EOF'
In Claude's Meet tab:
  1. Set mic claude_mic, speaker meet_out, camera Claude.
  2. Click "Join here too".
  3. People > ⋮ next to "(You)" > Stop merging audio with nearby devices.
EOF

"$bin/meet-voice.py"
