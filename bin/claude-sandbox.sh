#!/usr/bin/env bash
# stolen from glitchcrab https://gigantic.slack.com/archives/C05DCHUKTFH/p1773071560428739?thread_ts=1773071457.451679&cid=C05DCHUKTFH

set -eu

bwrap \
    --uid "$(id -u)"                                                \
    --gid "$(id -g)"                                                \
    --ro-bind   /bin                      /bin                      \
    --ro-bind   /etc/ca-certificates      /etc/ca-certificates      \
    --ro-bind   /etc/hosts                /etc/hosts                \
    --ro-bind   /etc/resolv.conf          /etc/resolv.conf          \
    --ro-bind   /etc/ssl                  /etc/ssl                  \
    --ro-bind   /lib                      /lib                      \
    --ro-bind   /lib64                    /lib64                    \
    --ro-bind   /opt/claude-code/         /opt/claude-code/         \
    --ro-bind   /run                      /run                      \
    --ro-bind   /usr                      /usr                      \
    --bind      "$HOME/.claude"           "$HOME/.claude"           \
    --bind      "$HOME/.claude.json"      "$HOME/.claude.json"      \
    --bind      "$HOME/.gnupg"            "$HOME/.gnupg"            \
    --ro-bind   "$HOME/.gitconfig"        "$HOME/.gitconfig"        \
    --ro-bind   "$HOME/.local"            "$HOME/.local"            \
    --ro-bind   "$CLAUDE_CONFIG_MCP_DIR"  "$CLAUDE_CONFIG_MCP_DIR"  \
    --bind      "$PWD"                    "$PWD"                    \
    --dev-bind  /dev                      /dev                      \
    --proc      /proc                                               \
    --tmpfs     /tmp                                                \
    --bind-try  "/tmp/tmux-$(id -u)"      "/tmp/tmux-$(id -u)"      \
    --share-net                                                     \
    --unshare-pid                                                   \
    --die-with-parent                                               \
    --chdir "$PWD"                                                  \
    /usr/bin/claude "$@" # start Claude and pass all arguments through
