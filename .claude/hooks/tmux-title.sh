#!/usr/bin/env bash

# Name the tmux window after Claude Code's own session title, and hand the
# window back to tmux when the session ends.
#
# Claude Code appends {"type":"ai-title","aiTitle":...} records to the
# transcript as it (re)titles the session, so the last one is the current name.

# Nothing to do outside tmux.
[[ -n "$TMUX_PANE" ]] || exit 0

INPUT="$(cat -)"

# rename-window turns automatic-rename off for the window, so turning it back
# on both restores tmux's naming and drops the title we set.
if [[ "$(echo "$INPUT" | jq -r '.hook_event_name')" == "SessionEnd" ]]; then
  tmux set-window-option -t "$TMUX_PANE" automatic-rename on 2>/dev/null
  exit 0
fi

TRANSCRIPT="$(echo "$INPUT" | jq -r '.transcript_path | strings')"
[[ -f "$TRANSCRIPT" ]] || exit 0

# Last title wins, trimmed to the first 3 words to keep the status bar short.
TITLE="$(grep '"type":"ai-title"' "$TRANSCRIPT" \
  | tail -1 \
  | jq -r '.aiTitle | strings' \
  | awk '{print tolower($1), tolower($2), tolower($3)}')"

[[ -n "${TITLE// /}" ]] || exit 0

tmux rename-window -t "$TMUX_PANE" "$TITLE" 2>/dev/null
exit 0
