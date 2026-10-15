#!/usr/bin/env bash
# Create or remove the virtual audio devices that connect meet-voice.py to a Meet tab.
#
# Usage: meet-audio.sh up|down
#
#   meet_out    sink    Meet tab speaker. meet-voice.py records its monitor.
#   claude_out  sink    meet-voice.py plays replies here.
#   claude_mic  source  Meet tab mic, remapped from claude_out.monitor.
set -euo pipefail

case ${1:-} in
up)
  for sink in meet_out claude_out; do
    pactl list short sinks | grep -qw "$sink" ||
      pactl load-module module-null-sink sink_name="$sink" sink_properties=device.description="$sink" >/dev/null
  done
  pactl list short sources | grep -qw claude_mic ||
    pactl load-module module-remap-source master=claude_out.monitor source_name=claude_mic \
      source_properties=device.description=claude_mic >/dev/null
  ;;
down)
  pactl list short modules |
    awk '/sink_name=(meet_out|claude_out)|source_name=claude_mic/ {print $1}' |
    xargs -r -n1 pactl unload-module
  ;;
*)
  echo "usage: $0 up|down" >&2
  exit 1
  ;;
esac
