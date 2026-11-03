# shellcheck shell=bash
# Sourced by beam-up.sh and beam-attach.sh.

# Writes a tar of the local login and settings to stdout, for
# beam-remote-copy.sh. Each member is renamed to its destination path in the
# pod. Arguments add tar options and members.
beam_tar() {
  tar -cz \
    --transform 's,^\.claude\.json$,run/claude/config/.claude.json.new,S' \
    --transform 's,^\.credentials\.json$,run/claude/config/.credentials.json.new,S' \
    --transform 's,^\.claude/,home/node/.claude/,S' \
    -C "$(dirname "$(readlink -f "$HOME/.claude.json")")" .claude.json \
    -C "$HOME/.claude" .credentials.json \
    -C "$HOME" .claude/settings.json .claude/CLAUDE.md .claude/keybindings.json \
    .claude/agents .claude/skills .claude/plugins \
    "$@"
}
