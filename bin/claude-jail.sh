#!/usr/bin/env bash
# Run Claude in a bubblewrap jail, at one of three isolation levels.
#
# Usage: claude-jail.sh [-m MODE] [writable-dir] [claude args...]
#
#   standard      (default) the whole home directory is visible through a
#                 throwaway overlay, so every tool config (kube, aws, gh,
#                 docker, gcloud, ...) is there and writes to it are discarded.
#                 Only <writable-dir> is bound read-write onto the host.
#                 Network on.
#   network-only  no host filesystem: tmpfs home, tmpfs workspace. Only
#                 ~/.claude comes in, through an overlay, so Claude can start
#                 and authenticate. Network on. Takes no <writable-dir>.
#   docker        standard plus a nested rootless podman, with its storage in
#                 tmpfs and its cgroups in your own delegated cgroup subtree.
#                 `docker` runs podman. Containers cannot touch the host.
#                 Weaker than standard: cgroup and network namespaces are
#                 shared with the host, podman needs both.

set -eu

mode=standard
case "${1:-}" in
    -m|--mode) mode=${2:?missing mode}; shift 2;;
esac

case "$mode" in
    standard|docker|network-only) ;;
    *) echo "unknown mode: $mode (standard, network-only, docker)" >&2; exit 64;;
esac

home=$(realpath -e "$HOME")
uid=$(id -u)

# Secrets that no tool needs to do its job: directories become tmpfs, files
# become /dev/null. ~/.ssh and ~/.gnupg stay, git needs them.
masked_dirs=(
    "$HOME/.1password"
    "$HOME/.config/1Password"
    "$HOME/.config/Bitwarden"
    "$HOME/.config/BraveSoftware"
    "$HOME/.config/chromium"
    "$HOME/.config/google-chrome"
    "$HOME/.mozilla"
)
masked_files=(
    "$HOME/.aws/credentials"
    "$HOME/.bash_history"
    "$HOME/.zsh_history"
)

# TODO: add the variables you want Claude to see. The environment is cleared,
# so anything not listed here does not reach the jail.
keep_env=(
    HOME
    USER
    LOGNAME
    SHELL
    TERM
    COLORTERM
    LANG
    PATH
    ANTHROPIC_API_KEY
    CLAUDE_CONFIG_MCP_DIR
    CLAUDE_CONFIG_ICON_PATH
    KUBECONFIG
)

# Mounts every mode shares.
common=(
    --clearenv
    --uid "$uid"
    --gid "$(id -g)"
    --ro-bind     /usr                  /usr
    --ro-bind     /bin                  /bin
    --ro-bind     /sbin                 /sbin
    --ro-bind     /lib                  /lib
    --ro-bind     /lib64                /lib64
    --ro-bind     /etc                  /etc
    --ro-bind     /opt/claude-code      /opt/claude-code
    --ro-bind     /run/systemd/resolve  /run/systemd/resolve
    --symlink     /run                  /var/run
    --dev         /dev
    --proc        /proc
    --tmpfs       /tmp
    --tmpfs       "/run/user/$uid"
    --setenv      CLAUDE_JAIL           "$mode"
    --die-with-parent
)

# network-only already has a tmpfs home, nothing to mask there.
mask=()
if [ "$mode" != network-only ]; then
    for p in "${masked_dirs[@]}"; do
        [ -d "$p" ] && mask+=(--tmpfs "$p")
    done
    for p in "${masked_files[@]}"; do
        [ -f "$p" ] && mask+=(--ro-bind /dev/null "$p")
    done
fi

env_args=()
for v in "${keep_env[@]}"; do
    [ -n "${!v:-}" ] && env_args+=(--setenv "$v" "${!v}")
done

mounts=()
unshare=(--unshare-all --share-net)
workdir=
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

if [ "$mode" = network-only ]; then
    # Nothing of the host filesystem, except Claude's own config and
    # credentials, without which it cannot start.
    cp "$home/.claude.json" "$scratch/claude.json"
    mounts+=(
        --tmpfs       "$home"
        --overlay-src "$home/.claude"
        --tmp-overlay "$home/.claude"
        --bind        "$scratch/claude.json" "$home/.claude.json"
        --tmpfs       /work
    )
    workdir=/work
else
    if [ $# -lt 1 ]; then
        echo "usage: ${0##*/} [-m MODE] <writable-dir> [claude args...]" >&2
        exit 64
    fi
    workdir=$(realpath -e "$1") || exit 64
    shift

    case "$home/" in
        "$workdir"/*) echo "refusing: $workdir is or contains \$HOME" >&2; exit 64;;
    esac
    if [ "$workdir" = "/" ]; then
        echo "refusing to make / writable" >&2
        exit 64
    fi

    # Writes to the home overlay land in tmpfs and are discarded on exit, so
    # sessions, /model and plugin installs do not persist.
    mounts+=(
        --overlay-src "$home"
        --tmp-overlay "$home"
        --ro-bind-try "${CLAUDE_CONFIG_MCP_DIR:-/nonexistent}" "${CLAUDE_CONFIG_MCP_DIR:-/nonexistent}"
        --bind        "$workdir" "$workdir"
    )
fi

if [ "$mode" = docker ]; then
    # Podman runs with a single uid mapping: empty subuid/subgid files keep it
    # from asking for ranges it cannot get inside the jail, and vfs with
    # ignore_chown_errors keeps image layers unpacking under that one uid.
    # Storage lives in tmpfs, so images are pulled again every session.
    : > "$scratch/subid"
    cat > "$scratch/storage.conf" <<EOF
[storage]
driver = "vfs"
runroot = "/tmp/podman/run"
graphroot = "/tmp/podman/store"
[storage.options.vfs]
ignore_chown_errors = "true"
EOF
    cat > "$scratch/containers.conf" <<EOF
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
EOF
    printf '#!/bin/sh\nexec podman "$@"\n' > "$scratch/docker"
    chmod +x "$scratch/docker"

    # Podman needs to write cgroups and to see the pids it puts in them, so the
    # cgroup namespace stays shared and the host cgroup subtree systemd
    # delegates to this user is bound as the cgroup root.
    cgroup="/sys/fs/cgroup/user.slice/user-$uid.slice/user@$uid.service"
    unshare=(--unshare-user --unshare-ipc --unshare-pid --unshare-uts)
    mounts+=(
        --ro-bind   /sys                 /sys
        --bind      "$cgroup"            /sys/fs/cgroup
        --dev-bind  /dev/net/tun         /dev/net/tun
        --tmpfs     /var/tmp
        --ro-bind   "$scratch/subid"     /etc/subuid
        --ro-bind   "$scratch/subid"     /etc/subgid
        --ro-bind   "$scratch"           "$scratch"
        --setenv    CONTAINERS_STORAGE_CONF "$scratch/storage.conf"
        --setenv    CONTAINERS_CONF         "$scratch/containers.conf"
        --setenv    PATH                    "$scratch:$PATH"
    )
fi

# No exec: the shell stays around to clean up $scratch when bwrap exits.
bwrap \
    "${common[@]}" \
    "${env_args[@]}" \
    "${mounts[@]}" \
    "${mask[@]}" \
    "${unshare[@]}" \
    --chdir "$workdir" \
    /usr/bin/claude "$@"
