#!/usr/bin/env bash
# Stop hook: read the last assistant reply aloud through speech-dispatcher (piper).
# Off unless CLAUDE_SPEAK=1 (claudy --speak).
[[ ${CLAUDE_SPEAK:-} == 1 ]] || exit 0
input=$(cat)
text=$(jq -r '.last_assistant_message // empty' <<<"$input")
if [[ -z $text ]]; then
  transcript=$(jq -r '.transcript_path // empty' <<<"$input")
  [[ -f $transcript ]] && text=$(jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // empty' "$transcript")
fi
[[ -z $text ]] && exit 0
# Drop code blocks, URLs and markdown symbols.
text=$(sed '/^```/,/^```/d' <<<"$text" | sed -E 's#https?://[^ ]+##g; s/[`*#|>_]//g')
spd-say -C
setsid -f spd-say -w -- "$text" >/dev/null 2>&1
