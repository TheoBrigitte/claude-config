#!/usr/bin/env bash
# stolen from glitchcrab https://gigantic.slack.com/archives/C05DCHUKTFH/p1773071560428739?thread_ts=1773071457.451679&cid=C05DCHUKTFH

set -eu

# Config the *host* Claude executes (hooks, statusline, skills, agents, plugins)
# or that defines its permissions must not be writable from inside the sandbox;
# these get re-mounted read-only on top of the writable ~/.claude bind below.
ro_config=()
for p in settings.json .env policy-limits.json CLAUDE.md statusline-command.sh \
         hooks agents skills plugins; do
    ro_config+=(--ro-bind-try "$HOME/.claude/$p" "$HOME/.claude/$p")
done

# ~/.local is read-only (it holds unrelated app state and $HOME/.local/bin is on
# the host PATH); Claude's own state dirs are punched back through as writable.
rw_state=()
for p in state/claude state/claude-cli-nodejs state/claude-status share/claude; do
    rw_state+=(--bind-try "$HOME/.local/$p" "$HOME/.local/$p")
done

bwrap \
    --uid "$(id -u)"                                                \
    --gid "$(id -g)"                                                \
    --ro-bind   /bin                      /bin                      \
    --ro-bind   /etc/ca-certificates      /etc/ca-certificates      \
    --ro-bind   /etc/hosts                /etc/hosts                \
    --ro-bind   /etc/passwd               /etc/passwd               \
    --ro-bind   /etc/group                /etc/group                \
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
    "${rw_state[@]}"                                                \
    --overlay-src "$HOME/pkg"                                       \
    --tmp-overlay "$HOME/pkg"                                       \
    --ro-bind   "$CLAUDE_CONFIG_MCP_DIR"  "$CLAUDE_CONFIG_MCP_DIR"  \
    --bind      "$PWD"                    "$PWD"                    \
    "${ro_config[@]}"                                               \
    --ro-bind-try "$HOME/.docker"         "$HOME/.docker"           \
    --symlink   /run                      /var/run                  \
    --dev       /dev                                                \
    --proc      /proc                                               \
    --tmpfs     /tmp                                                \
    --bind-try  "/tmp/tmux-$(id -u)"      "/tmp/tmux-$(id -u)"      \
    --unshare-all                                                   \
    --share-net                                                     \
    --die-with-parent                                               \
    --chdir "$PWD"                                                  \
    /usr/bin/claude "$@" # start Claude and pass all arguments through
