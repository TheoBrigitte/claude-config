#!/bin/bash
#
# Format and display a status line for the latest Claude API call, showing model, context usage, cost, duration, and API status.

# Input data
input="$(cat)"

MODEL="$(echo "$input" | jq -r '.model.display_name')"
COST="$(echo "$input" | jq -r '.cost.total_cost_usd // 0')"
CONTEXT_CURRENT_USAGE="$(echo "$input" | jq -r '.context_window.current_usage | add? // 0')"
CONTEXT_OUTPUT_TOKENS="$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')"
CONTEXT_MAX_TOKENS="$(echo "$input" | jq -r '.context_window.context_window_size // 0')"
CONTEXT_PCT="$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)"
DURATION_MS="$(echo "$input" | jq -r '.cost.total_duration_ms // 0')"

# Colors
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

# Layout
CONTEXT_BAR_SIZE=40
MIDDLE_SEPARATOR=" | "

TERMINAL_WIDTH="$(stty size -F /dev/tty | awk '{print $2}')"
# Reduce context bar size for narrow terminals to prevent wrapping.
[[ "$TERMINAL_WIDTH" -lt 115 ]] && CONTEXT_BAR_SIZE=20

# Pick bar color based on context usage
# > 90% = red, to notify about hitting limits soon.
# > 40% = yellow, to indicate that context has reached a significant portion, reminding about the "dumb zone" (see https://www.youtube.com/watch?v=rmvDxxNubIg).
if [[ "$CONTEXT_PCT" -ge 90 ]]; then BAR_COLOR="$RED"
elif [[ "$CONTEXT_PCT" -ge 40 ]]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

# Model formatting
MODEL_FMT="${CYAN}[$MODEL]${RESET}"

# Context bar formatting
FILLED="$((CONTEXT_PCT * CONTEXT_BAR_SIZE / 100))"; EMPTY="$((CONTEXT_BAR_SIZE - FILLED))"
BAR="$(printf "%${FILLED}s" | tr ' ' '#')$(printf "%${EMPTY}s" | tr ' ' '-')"
CONTEXT_USED="$(numfmt --to=si --round=down "${CONTEXT_CURRENT_USAGE}")"
CONTEXT_MAX="$(numfmt --to=si "$CONTEXT_MAX_TOKENS")"
CONTEXT_FMT="${BAR_COLOR}${BAR}${RESET} ${CONTEXT_PCT}% (${CONTEXT_USED}/${CONTEXT_MAX} tokens)"

# Duration formatting
DURATION_MINS="$((DURATION_MS / 60000))"; DURATION_SECS="$(((DURATION_MS % 60000) / 1000))"
DURATION_FMT="⏱️ ${DURATION_MINS}m ${DURATION_SECS}s"

# Cost formatting
COST_FMT="${YELLOW}$(printf '$%.2f' "${COST/./,}")${RESET}"

# API status formatting with caching (valid for 10 minutes to avoid excessive API calls)
API_STATUS_OK="🟢"
API_STATUS_KO="🟡"
API_STATUS_FILE=~/.local/state/claude-status/api_status.txt
API_STATUS="$(find "$API_STATUS_FILE" -mmin -10 -exec cat {} \;)"
if [[ -z "$API_STATUS" ]]; then
  mkdir -p "$(dirname "$API_STATUS_FILE")"
  api_status="$(curl -LSs https://status.claude.com/api/v2/status.json | jq -r '.status.description')"
  if echo "$api_status" | grep -iq "operational"; then
    API_STATUS=" | $API_STATUS_OK"
  else
    API_STATUS="\n$API_STATUS_KO $api_status"
  fi
  echo -e "$API_STATUS" > "$API_STATUS_FILE"
fi
API_STATUS_FMT="${API_STATUS}"

# Output status line
if [[ "$TERMINAL_WIDTH" -lt 90 ]]; then
  STATUS_LINE="${CONTEXT_FMT}\n${MODEL_FMT} | ${COST_FMT} | ${DURATION_FMT}${API_STATUS_FMT}"
else
  STATUS_LINE="${MODEL_FMT} ${CONTEXT_FMT} | ${COST_FMT} | ${DURATION_FMT}${API_STATUS_FMT}"
fi

echo -e "$STATUS_LINE"

## Debug
#{
#  #echo "=== INPUT ==="
#  echo "$input"
#  #echo "=== VARIABLES ==="
#  #echo "CONTEXT_PCT   : $CONTEXT_PCT"
#  #echo "FILLED: $FILLED"
#  #echo "EMPTY : $EMPTY"
#  #echo "COST  : $COST"
#  #echo "COST_FMT: $COST_FMT"
#} >> claude-status.json
