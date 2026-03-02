#!/bin/bash

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

# Pick bar color based on context usage
if [ "$CONTEXT_PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$CONTEXT_PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

# Model formatting
MODEL_FMT="${CYAN}[$MODEL]${RESET}"

# Context bar formatting
FILLED="$((CONTEXT_PCT * 40 / 100))"; EMPTY="$((40 - FILLED))"
BAR="$(printf "%${FILLED}s" | tr ' ' '#')$(printf "%${EMPTY}s" | tr ' ' '-')"
CONTEXT_USED="$(numfmt --to=si --round=down "${CONTEXT_CURRENT_USAGE}")"
CONTEXT_MAX="$(numfmt --to=si "$CONTEXT_MAX_TOKENS")"
CONTEXT_FMT="${BAR_COLOR}${BAR}${RESET} ${CONTEXT_PCT}% (${CONTEXT_USED}/${CONTEXT_MAX} tokens)"

# Duration formatting
DURATION_MINS="$((DURATION_MS / 60000))"; DURATION_SECS="$(((DURATION_MS % 60000) / 1000))"
DURATION_FMT="⏱️ ${DURATION_MINS}m ${DURATION_SECS}s"

# Cost formatting
COST_FMT="${YELLOW}$(printf '$%.2f' "${COST/./,}")${RESET}"

# Output status line
echo -e "${MODEL_FMT}  ${CONTEXT_FMT} | ${COST_FMT} | ${DURATION_FMT}"

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
