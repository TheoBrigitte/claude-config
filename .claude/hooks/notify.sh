#!/usr/bin/env bash

# Skip notification only if this is the active tmux window AND the terminal window is focused
#TMUX_WINDOW_ACTIVE="$(tmux display-message -pt "$TMUX_PANE" '#{window_active}')"
#CLIENT_FOCUSED="$(tmux display-message -pt "$TMUX_PANE" '#{client_flags}' | grep -c 'focused')"
#if [[ "$TMUX_WINDOW_ACTIVE" -eq "1" ]] && [[ "$CLIENT_FOCUSED" -gt "0" ]]; then
#  exit
#fi
TMUX_WINDOW_INDEX="$(tmux display-message -p -F '#{window_index}' -t "$TMUX_PANE" || echo none)"
SUMMARY="Claude #${TMUX_WINDOW_INDEX}"
CLAUDE_CONFIG_ICON_PATH="${CLAUDE_CONFIG_ICON_PATH:-$HOME/.claude/claude-color.svg}"

# Ring the bell in our own pane so tmux turns the window title red.
# Hooks have no controlling terminal, so /dev/tty is not usable: ask tmux
# for the pane's tty and write there. Not stdout, that is the JSON channel.
ring_bell() {
  local pane_tty
  pane_tty="$(tmux display-message -p -F '#{pane_tty}' -t "$TMUX_PANE" 2>/dev/null)"
  [[ -n "$pane_tty" ]] && printf '\a' > "$pane_tty"
}

# Read hook input
INPUT="$(cat -)"
echo "$INPUT" > "/home/theo/projects/ai/notifications-dump/$(uuidgen).json"

# Handle non permission request, and assume those are Claude noification messages
if echo "$INPUT" | jq -e '.hook_event_name != "PermissionRequest"' 1>/dev/null; then
  # Ignore permission notifications which would otherwise be duplicated from the PermissionRequest handling below.
  NOTIFICATION_TYPE="$(echo "$INPUT" | jq -r '.notification_type')"
  if [[ "$NOTIFICATION_TYPE" == "permission_prompt" ]]; then
    exit
  fi

  # Build the notification message
  MESSAGE="$(echo "$INPUT" | jq -r '.message | strings')"
  TITLE="$(echo "$INPUT" | jq -r '.title | strings')"
  if [[ -n "$TITLE" ]]; then
    MESSAGE="<b>$TITLE</b>\n${MESSAGE}"
  fi

  ring_bell
  notify-send -i "$CLAUDE_CONFIG_ICON_PATH" "$SUMMARY" "${MESSAGE}"
  exit 0
fi

# Handle PermissionRequest messages

ring_bell

# Read the permission request's tool and command from the input
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name | strings')"

# Handle different tools formats
MESSAGE=""
case "$TOOL_NAME" in
  AskUserQuestion)
    MESSAGE="Question: $(echo "$INPUT" | jq -r '.tool_input.questions | first.question | strings')"
    # Send questions as notifications without actions
    notify-send -i "$CLAUDE_CONFIG_ICON_PATH" "$SUMMARY" "$MESSAGE"
    exit 0;;

  Bash)
    MESSAGE="$(echo "$INPUT" | jq -r '(.tool_input.description | strings), ("Bash( " + .tool_input.command | strings + " )")')";;
  Edit)
    MESSAGE="$(echo "$INPUT" | jq -r '"Edit( " + .tool_input.file_path | strings + " )"')";;
  *)
    MESSAGE="$TOOL_NAME";;
esac

# Send the notification, with allow and deny actions
RESPONSE="$(notify-send -i "$CLAUDE_CONFIG_ICON_PATH" --wait --expire-time 5000 --action=ALLOW=Allow --action=DENY=Deny "${SUMMARY} - Permissions request" "${MESSAGE}")"

# Handle responses action response
case "$RESPONSE" in
  ALLOW)
    jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow"
    }
  }
}'
  ;;
  DENY)
    jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "User denied permission for this action."
    }
  }
}'
  ;;
esac

# No response given (e.g. timeout)
# Leave the decision to the agent UI.
exit 0
