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

# Terminal we are attached to. Hooks get no controlling terminal, so /dev/tty
# is unusable, and under bwrap /tmp is a tmpfs so the tmux socket is not there
# either. The claude process up the tree does hold the pane's pty, and /dev is
# bind-mounted, so walk up and use that.
terminal() {
  local pid="$PPID" tty
  while [[ "$pid" -gt 1 ]]; do
    tty="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
    if [[ -n "$tty" && "$tty" != "?" ]]; then
      echo "/dev/$tty"
      return 0
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
  done
  return 1
}

# Ring the bell so tmux turns the window title red.
# Not stdout: that is the hook's JSON response channel.
ring_bell() {
  local tty
  tty="$(terminal)" || return 0
  printf '\a' > "$tty" 2>/dev/null
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
