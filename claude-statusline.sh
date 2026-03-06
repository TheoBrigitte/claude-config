#!/bin/bash
#
# Format and display a status line for the latest Claude API call, showing model, context usage, cost, duration, and API status.

# Input data
input="$(cat)"

MODEL="$(echo "$input" | jq -r '.model.display_name')"
COST="$(echo "$input" | jq -r '.cost.total_cost_usd // 0')"
CONTEXT_CURRENT_USAGE="$(echo "$input" | jq -r '.context_window.current_usage | add? // 0')"
CONTEXT_MAX_TOKENS="$(echo "$input" | jq -r '.context_window.context_window_size // 0')"
CONTEXT_PCT="$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)"
DURATION_MS="$(echo "$input" | jq -r '.cost.total_duration_ms // 0')"

# Colors
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

TERMINAL_WIDTH="$(($(stty size -F /dev/tty | awk '{print $2}') - 5))"
CONTEXT_BAR_SIZE="$((TERMINAL_WIDTH / 3))"
[[ "$CONTEXT_BAR_SIZE" -gt 40 ]] && CONTEXT_BAR_SIZE=40
[[ "$CONTEXT_BAR_SIZE" -lt 10 ]] && CONTEXT_BAR_SIZE=0

# Pick bar color based on context usage
# > 90% = red, to notify about hitting limits soon.
# > 40% = yellow, to indicate that context has reached a significant portion, reminding about the "dumb zone" (see https://www.youtube.com/watch?v=rmvDxxNubIg).
if [[ "$CONTEXT_PCT" -ge 90 ]]; then BAR_COLOR="$RED"
elif [[ "$CONTEXT_PCT" -ge 40 ]]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

# Print status line
print_status_line() {
  STATUS_PARTS=()
  SEPARATOR=" | "
  while [[ $# -gt 0 ]]; do
    if [[ -z "$1" ]]; then
      shift
      continue
    fi
    if [[ "${#STATUS_PARTS[@]}" -eq 0 ]]; then
      STATUS_PARTS+=("$1")
    else
      PART="${SEPARATOR}$1"
      PART_LEN="${#PART}"
      if [[ $((${#STATUS_PARTS[-1]} + ${PART_LEN})) -ge "$TERMINAL_WIDTH" ]]; then
        STATUS_PARTS+=("${1}")
      else
        STATUS_PARTS[-1]="${STATUS_PARTS[-1]}${PART}"
      fi
    fi
    shift
  done
  echo -e "$(printf "%s\n" "${STATUS_PARTS[@]}")"
}

# Model formatting
MODEL_FMT="${CYAN}[$MODEL]${RESET}"
# Hide model if terminal is too narrow to avoid clutter, as it's less critical than context usage and cost.
 [[ "$TERMINAL_WIDTH" -lt 90 ]] && MODEL_FMT=""

# Context bar formatting
FILLED="$((CONTEXT_PCT * CONTEXT_BAR_SIZE / 100))"; EMPTY="$((CONTEXT_BAR_SIZE - FILLED))"
BAR="$(printf "%${FILLED}s" | tr ' ' '#')$(printf "%${EMPTY}s" | tr ' ' '-')"
CONTEXT_USED="$(numfmt --to=si --round=down "${CONTEXT_CURRENT_USAGE}")"
CONTEXT_MAX="$(numfmt --to=si "$CONTEXT_MAX_TOKENS")"
CONTEXT_TOKEN_FMT="(${CONTEXT_USED}/${CONTEXT_MAX} tokens)"
CONTEXT_BAR_FMT="${BAR_COLOR}${BAR}${RESET}"
CONTEXT_FMT="${CONTEXT_PCT}%"
[[ "$((${#CONTEXT_FMT} + ${#CONTEXT_TOKEN_FMT}))" -lt "$TERMINAL_WIDTH" ]] && CONTEXT_FMT="$CONTEXT_FMT $CONTEXT_TOKEN_FMT"
[[ "$((${#CONTEXT_FMT} + ${#CONTEXT_BAR_FMT}))" -lt "$TERMINAL_WIDTH" ]] && [[ "$CONTEXT_BAR_SIZE" -gt 0 ]] && CONTEXT_FMT="$CONTEXT_BAR_FMT $CONTEXT_FMT"

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
    API_STATUS="$API_STATUS_OK"
  else
    API_STATUS="$API_STATUS_KO degraded"
  fi
  echo -e "$API_STATUS" > "$API_STATUS_FILE"
fi
API_STATUS_FMT="${API_STATUS}"

# Output status line
print_status_line "$MODEL_FMT" "$CONTEXT_FMT" "$COST_FMT" "$DURATION_FMT" "$API_STATUS_FMT"

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


## Examples
# ---
# [Opus 4.6(1 M)]  ##------------------ 10% (198k/200k tokens) | $11,22 | ⏱️ 59m 59s
# ---
# [Opus 4.6 (1M context)]  ####------------------------------------ 99% (100k/1,0M tokens) | $10,22 | ⏱️ 59m 59s
# ---
# [Opus 4.6 (1M context)]  ####---------------- 99% (100k/1,0M tokens) | $10,22 | ⏱️ 59m 59s
# ---
# [Opus 4.6 (1M context)]  ####---------------- 99% (100k/1,0M tokens)
# $10,22 | ⏱️ 59m 59s
# ---
