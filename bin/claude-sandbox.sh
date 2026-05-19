#!/usr/bin/env bash
# stolen from glitchcrab https://gigantic.slack.com/archives/C05DCHUKTFH/p1773071560428739?thread_ts=1773071457.451679&cid=C05DCHUKTFH

set -eu

bwrap \
    --uid "$(id -u)" \
    --gid "$(id -g)" \
    --ro-bind /usr /usr \
    --ro-bind /lib /lib \
    --ro-bind /lib64 /lib64 \
    --ro-bind /bin /bin \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --ro-bind /etc/hosts /etc/hosts \
    --ro-bind /etc/ssl /etc/ssl \
    --ro-bind /etc/ca-certificates /etc/ca-certificates \
    --ro-bind /usr/share/ca-certificates /usr/share/ca-certificates \
    --ro-bind /opt/claude-code/ /opt/claude-code/ \
    --ro-bind "$HOME/.gitconfig" "$HOME/.gitconfig" \
    --bind "$HOME/.gnupg" "$HOME/.gnupg" \
    --ro-bind "$HOME/.local" "$HOME/.local" \
    --ro-bind "$CLAUDE_CONFIG_MCP_DIR" "$CLAUDE_CONFIG_MCP_DIR" \
    --bind "$HOME/.claude" "$HOME/.claude" \
    --bind "$HOME/.claude.json" "$HOME/.claude.json" \
    --bind "$PWD" "$PWD" \
    --ro-bind /run /run \
    --tmpfs /tmp \
    --proc /proc \
    --dev-bind /dev /dev \
    --share-net \
    --unshare-pid \
    --die-with-parent \
    --chdir "$PWD" \
    /usr/bin/claude "$@" # start Claude and pass all arguments through
