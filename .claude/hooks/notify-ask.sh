#!/usr/bin/env bash

QUESTION="$(jq -r '( .tool_input.questions | first.question | strings | "Question: " + . ) // ( .tool_input.description | strings | "Permission request: " + . ) // .tool_name')"

notify-send -i /home/theo/projects/ai/claude-color.svg "Claude" "$QUESTION"

#INPUT="$(cat -)"

#SESSION_ID="$(echo "$INPUT" | jq -r '.session_id' | cut -c 1-8)"
#TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name')"

#notify-send -i /home/theo/projects/ai/claude-color.svg "Claude" "input requested"
#echo "$INPUT" > "/home/theo/projects/ai/${SESSION_ID}.${TOOL_NAME}.tool_input.json"

#TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name')"
#QUESTION="$(echo "$INPUT" | jq -r '( .tool_input.questions | first.question | strings | "Question: " + . ) // ( .tool_input.description | strings | "Permission request: " + . ) // .tool_name')"
#
#notify-send -i /home/theo/projects/ai/claude-color.svg "Claude" "$QUESTION"
#if [[ -n "$QUESTION" ]]; then
#  notify-send -i /home/theo/projects/ai/claude-color.svg "Claude" "Asks: $QUESTION"
#else
#  notify-send -i /home/theo/projects/ai/claude-color.svg "Claude" "Permission requested for ${TOOL_NAME}"
#fi

#if [[ "$TOOL_NAME" == "AskUserQuestion" ]]; then
#  QUESTION="$(echo "$INPUT" | jq -r '.tool_input.questions|first.question')"
#  notify-send -i /home/theo/projects/ai/claude-color.svg "Claude" "$QUESTION"
#  exit 0
#fi

#if [[ "$TOOL_NAME" == "PermissionRequest" ]]; then
#  :
#fi


#COMMAND="$(echo "$INPUT" | jq -cr '.tool_input.command')"

#TMUX_WINDOW="$(tmux display-message -p -F '#{window_index}' || echo none)"
#notify-send -i /home/theo/projects/ai/claude-color.svg "Claude" "Claude requests your input for <b>${COMMAND}</b> (tmux window <b>${TMUX_WINDOW}</b>)"

exit 0  # allow the command
