#!/usr/bin/env bash
# Run Claude in a bubblewrap jail, at one of three isolation levels.
#
# Usage: claude-sandbox.sh [-m MODE] [claude args...]
#
# The current directory is the one writable path. Inside a git repository, the
# whole working tree and its git dir are.
#
#   standard      (default) the whole home directory is visible through a
#                 throwaway overlay, so every tool config (kube, aws, gh,
#                 docker, gcloud, ...) is there and writes to it are discarded.
#                 Only the current directory is bound read-write onto the
#                 host. Network on.
#   network-only  no host filesystem: tmpfs home, tmpfs workspace. Only
#                 ~/.claude comes in, read-write, so Claude can start,
#                 authenticate and keep its history. Network on. The current
#                 directory is not mounted.
#   docker        standard plus the host docker socket and a rootless podman
#                 service socket. Weaker than standard: the daemons run
#                 containers on the host.

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
    GH_TOKEN
    GPG_TTY
    SSH_AUTH_SOCK
    # MCP server configs in $CLAUDE_CONFIG_MCP_DIR expand these.
    CONTEXT7_API_KEY
    GITHUB_TOKEN
    GRAFANA_ORG_ID
    GRAFANA_PASSWORD
    GRAFANA_SERVICE_ACCOUNT_TOKEN
    GRAFANA_URL
    GRAFANA_USERNAME
    INCIDENT_IO_API_KEY
    JINA_API_KEY
    N8N_API_KEY
    PAGERDUTY_USER_API_KEY
)

# gh keeps its token in the login keyring, which the jail cannot reach: it has
# no session bus. Resolve the token on the host and pass it in, so the keyring
# itself stays outside.
if [ -z "${GH_TOKEN:-}" ]; then
    GH_TOKEN=$(gh auth token 2>/dev/null) || true
fi

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
    # git signs commits, so gpg needs the socket of the agent already running
    # on the host, the one holding the unlocked key.
    --ro-bind-try "/run/user/$uid/gnupg"  "/run/user/$uid/gnupg"
    # The user namespace maps root to nobody, and ssh refuses a config file
    # not owned by root or the user. The drop-ins go, so git over ssh works.
    --tmpfs       /etc/ssh/ssh_config.d
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

# ~/.claude is bound read-write on the host: history, sessions and the OAuth
# token survive the jail. Claude refreshes that token in place and the refresh
# token rotates, so a refresh dropped with the overlay invalidates the token on
# the host too. Hooks are the exception: they run unsandboxed on the host, so
# the jail sees hooks/, settings.json and plugins/ read-only. Plugin installs
# therefore do not persist.
cdir=$(realpath -e "$home/.claude")

if [ "$mode" = network-only ]; then
    # Nothing of the host filesystem, except Claude's own config and
    # credentials, without which it cannot start.
    cp "$home/.claude.json" "$scratch/claude.json"
    mounts+=(
        --tmpfs       "$home"
        --bind        "$cdir" "$home/.claude"
        --bind        "$scratch/claude.json" "$home/.claude.json"
        --tmpfs       /work
    )
    cdest="$home/.claude"
    workdir=/work
else
    workdir=$(realpath -e "$PWD") || exit 64

    # Inside a git repository, the whole working tree is writable, and so is
    # the git dir, which a worktree or a submodule keeps outside it.
    writable=$workdir
    gitdir=
    if toplevel=$(git -C "$workdir" rev-parse --show-toplevel 2>/dev/null); then
        writable=$toplevel
        gitdir=$(git -C "$workdir" rev-parse --path-format=absolute --git-common-dir)
    fi

    case "$home/" in
        "$writable"/*) echo "refusing: $writable is or contains \$HOME" >&2; exit 64;;
    esac
    if [ "$writable" = "/" ]; then
        echo "refusing to make / writable" >&2
        exit 64
    fi

    # Writes to the home overlay are discarded on exit, so everything outside
    # ~/.claude and the working tree does not persist.
    mounts+=(
        --overlay-src "$home"
        --tmp-overlay "$home"
        --ro-bind-try "${CLAUDE_CONFIG_MCP_DIR:-/nonexistent}" "${CLAUDE_CONFIG_MCP_DIR:-/nonexistent}"
        --bind        "$cdir" "$cdir"
        --bind        "$writable" "$writable"
    )
    [ -n "$gitdir" ] && mounts+=(--bind "$gitdir" "$gitdir")
    # A socket seen through the overlay refuses connections: the agent's
    # directory is bound on top, so git over ssh can use the host keys.
    if [ -S "${SSH_AUTH_SOCK:-}" ]; then
        agent_dir=$(dirname "$SSH_AUTH_SOCK")
        mounts+=(--ro-bind "$agent_dir" "$agent_dir")
    fi
    cdest="$cdir"
fi

for p in hooks settings.json plugins; do
    [ -e "$cdir/$p" ] && mounts+=(--ro-bind "$cdir/$p" "$cdest/$p")
done

if [ "$mode" = docker ]; then
    # The host docker daemon and the rootless podman service, through their
    # sockets. Either one gives full control over what it runs.
    # The podman service runs on the host for the jail's lifetime.
    podman system service --time=0 "unix://$scratch/podman.sock" >/dev/null 2>&1 &
    svc=$!
    trap 'kill "$svc" 2>/dev/null; rm -rf "$scratch"' EXIT
    until [ -S "$scratch/podman.sock" ]; do sleep 0.1; done
    mounts+=(
        --bind-try /run/docker.sock /run/docker.sock
        --bind     "$scratch/podman.sock" "/run/user/$uid/podman/podman.sock"
        --setenv   CONTAINER_HOST "unix:///run/user/$uid/podman/podman.sock"
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
