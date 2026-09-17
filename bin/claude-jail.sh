#!/usr/bin/env bash
# Run Claude with a single writable directory.
#
# Everything outside the given directory is read-only: the whole home directory
# is mounted through a throwaway overlay, so Claude sees every tool config
# (kube, aws, gh, docker, gcloud, ...) and can write anywhere it likes, but the
# writes land in a tmpfs that is discarded when Claude exits. Only the directory
# passed as first argument is bound read-write onto the host.
#
# Usage: claude-jail.sh <writable-dir> [claude args...]

set -eu

if [ $# -lt 1 ]; then
    echo "usage: ${0##*/} <writable-dir> [claude args...]" >&2
    exit 64
fi

workdir=$(realpath -e "$1") || exit 64
shift

home=$(realpath -e "$HOME")
case "$home/" in
    "$workdir"/*) echo "refusing: $workdir is or contains \$HOME" >&2; exit 64;;
esac
if [ "$workdir" = "/" ]; then
    echo "refusing to make / writable" >&2
    exit 64
fi

# Claude state that must survive the session lives nowhere: everything under
# $HOME is overlaid. Sessions, /model and plugin installs do not persist.
bwrap \
    --uid "$(id -u)"                                                  \
    --gid "$(id -g)"                                                  \
    --ro-bind   /usr                      /usr                        \
    --ro-bind   /bin                      /bin                        \
    --ro-bind   /sbin                     /sbin                       \
    --ro-bind   /lib                      /lib                        \
    --ro-bind   /lib64                    /lib64                      \
    --ro-bind   /etc                      /etc                        \
    --ro-bind   /opt/claude-code          /opt/claude-code            \
    --ro-bind   /run/systemd/resolve      /run/systemd/resolve        \
    --overlay-src "$home"                                             \
    --tmp-overlay "$home"                                             \
    --ro-bind-try "${CLAUDE_CONFIG_MCP_DIR:-/nonexistent}" "${CLAUDE_CONFIG_MCP_DIR:-/nonexistent}" \
    --symlink   /run                      /var/run                    \
    --dev       /dev                                                  \
    --proc      /proc                                                 \
    --tmpfs     /tmp                                                  \
    --tmpfs     "/run/user/$(id -u)"                                  \
    --setenv    CLAUDE_JAIL               1                           \
    --unshare-all                                                     \
    --share-net                                                       \
    --die-with-parent                                                 \
    --bind      "$workdir"                "$workdir"                  \
    --chdir "$workdir"                                                \
    /usr/bin/claude "$@"
