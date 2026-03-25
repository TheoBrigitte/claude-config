#!/usr/bin/env bash

# If this is the active tmux window, skip the notification
if [[ "$(tmux display-message -pt "$TMUX_PANE" '#{window_active}')" -eq "1" ]]; then
  exit
fi
TMUX_WINDOW_INDEX="$(tmux display-message -p -F '#{window_index}' -t "$TMUX_PANE" || echo none)"
SUMMARY="Claude #${TMUX_WINDOW_INDEX}"

# Read hook input
INPUT="$(cat -)"

# Handle questions, those should be coming from the "PermissionRequest" hook event, but only checking for the presence of a question in the input.
QUESTION="$(echo "$INPUT" | jq -r '( .tool_input.questions | first.question | strings')"
if [[ -n "$QUESTION" ]]; then
  notify-send -i "$CLAUDE_CONFIG_ICON_PATH" "$SUMMARY" "Question: $QUESTION"
  exit 0
fi

# Handle permission requests
if echo "$INPUT" | jq -e '.hook_event_name == "PermissionRequest"' 1>/dev/null; then
  # Read the permission request's tool and command from the input
  REQUEST="$(echo "$INPUT" | jq -r '.tool_input.description, "<b>" + .tool_name +"( "+ .tool_input.command +" ) </b>"')"

  # Send the notification, with allow and deny actions
  RESPONSE="$(notify-send -i "$CLAUDE_CONFIG_ICON_PATH" --wait --expire-time 5000 --action=ALLOW=Allow --action=DENY=Deny "${SUMMARY} - Permission request" "$REQUEST")"

  # Handle responses
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
fi

# Assuming this is a notification message
NOTIFICATION_TYPE="$(echo "$INPUT" | jq -r '.notification_type')"
if [[ "$NOTIFICATION_TYPE" == "permission_prompt" ]]; then
  exit
fi

MESSAGE="$(echo "$INPUT" | jq -r '.message | strings')"
TITLE="$(echo "$INPUT" | jq -r '.title | strings')"
if [[ -n "$TITLE" ]]; then
  TITLE="<b>$TITLE</b>\n"
fi

notify-send -i "$CLAUDE_CONFIG_ICON_PATH" "$SUMMARY" "${TITLE}${MESSAGE}"
exit 0
