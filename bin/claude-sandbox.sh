#!/usr/bin/env bash
# Run Claude in a bubblewrap jail, at one of three isolation levels.
#
# Usage: claude-sandbox.sh [-m MODE] [-w DIR]... [--] [claude args...]
#
# Without -w, the current directory is writable. Inside a git repository, the
# whole working tree and its git dir are.
#
# With -w, the working directory is an empty tmpfs at /work, and each DIR is
# bound read-write in it under its basename: -w ~/src/foo is /work/foo. The
# current directory is not mounted. network-only mode rejects -w.
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
write_dirs=()
while [ $# -gt 0 ]; do
    case "$1" in
        -m|--mode) mode=${2:?missing mode}; shift 2;;
        -w|--write-dir) write_dirs+=("${2:?missing directory}"); shift 2;;
        --) shift; break;;
        *) break;;
    esac
done

case "$mode" in
    standard|docker|network-only) ;;
    *) echo "unknown mode: $mode (standard, network-only, docker)" >&2; exit 64;;
esac

if [ "$mode" = network-only ] && [ ${#write_dirs[@]} -gt 0 ]; then
    echo "network-only mode mounts no host directory, -w is not allowed" >&2
    exit 64
fi

home=$(realpath -e "$HOME")
uid=$(id -u)

# The CLAUDE_ prefixed tokens below.
. "$home/.config/shell/claude_secrets.sh"

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
    # The speak.sh Stop hook reads this.
    CLAUDE_SPEAK
    KUBECONFIG
    GPG_TTY
    SSH_AUTH_SOCK
    # MCP server configs in $CLAUDE_CONFIG_MCP_DIR expand these.
    CONTEXT7_API_KEY
    GRAFANA_ORG_ID
    GRAFANA_PASSWORD
    GRAFANA_SERVICE_ACCOUNT_TOKEN
    GRAFANA_URL
    GRAFANA_USERNAME
    JINA_API_KEY
    N8N_API_KEY
    # Claude Code exports its OpenTelemetry logs and metrics with these.
    CLAUDE_CODE_ENABLE_TELEMETRY
    OTEL_LOGS_EXPORTER
    OTEL_METRICS_EXPORTER
    OTEL_EXPORTER_OTLP_LOGS_PROTOCOL
    OTEL_EXPORTER_OTLP_LOGS_ENDPOINT
    OTEL_EXPORTER_OTLP_LOGS_HEADERS
    OTEL_EXPORTER_OTLP_METRICS_PROTOCOL
    OTEL_EXPORTER_OTLP_METRICS_ENDPOINT
    OTEL_EXPORTER_OTLP_METRICS_HEADERS
    OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE
)

# Passed in with the CLAUDE_ prefix stripped: GITHUB_TOKEN, SLACK_TOKEN, ...
prefixed_env=(
    CLAUDE_GITHUB_TOKEN
    CLAUDE_PAGERDUTY_USER_API_KEY
    # The circleci CLI reads its token from here, in every mode.
    CLAUDE_CIRCLE_TOKEN
    CLAUDE_SLACK_TOKEN
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
    # The Playwright MCP server launches Chrome from here.
    --ro-bind-try /opt/google           /opt/google
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
for v in "${prefixed_env[@]}"; do
    [ -n "${!v:-}" ] && env_args+=(--setenv "${v#CLAUDE_}" "${!v}")
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
# the jail sees hooks/, settings.json and plugins/ read-only, except for a
# throwaway overlay on plugins/cache. Plugin installs therefore do not persist.
cdir=$(realpath -e "$home/.claude")

# Claude asks whether to trust the working directory and records the answer in
# ~/.claude.json, which the jail never writes back: the answer would be asked
# again every session. The directory is trusted up front, on the host.
trust() {
    jq -e --arg d "$2" '.projects[$d].hasTrustDialogAccepted == true' "$1" >/dev/null && return
    local f
    f=$(realpath -e "$1")
    jq --arg d "$2" '.projects[$d].hasTrustDialogAccepted = true' "$f" > "$f.trust.$$"
    mv "$f.trust.$$" "$f"
}

if [ "$mode" = network-only ]; then
    # Nothing of the host filesystem, except Claude's own config and
    # credentials, without which it cannot start.
    cp "$home/.claude.json" "$scratch/claude.json"
    trust "$scratch/claude.json" /work
    mounts+=(
        --tmpfs       "$home"
        --bind        "$cdir" "$home/.claude"
        --bind        "$scratch/claude.json" "$home/.claude.json"
        --tmpfs       /work
    )
    cdest="$home/.claude"
    workdir=/work
else
    refuse() {
        case "$home/" in
            "$1"/*) echo "refusing: $1 is or contains \$HOME" >&2; exit 64;;
        esac
        if [ "$1" = "/" ]; then
            echo "refusing to make / writable" >&2
            exit 64
        fi
    }

    # Writes to the home overlay are discarded on exit, so everything outside
    # ~/.claude and the writable directories does not persist.
    mounts+=(
        --overlay-src "$home"
        --tmp-overlay "$home"
        --ro-bind-try "${CLAUDE_CONFIG_MCP_DIR:-/nonexistent}" "${CLAUDE_CONFIG_MCP_DIR:-/nonexistent}"
        --bind        "$cdir" "$cdir"
    )

    if [ ${#write_dirs[@]} -eq 0 ]; then
        workdir=$(realpath -e "$PWD") || exit 64

        # Inside a git repository, the whole working tree is writable, and so
        # is the git dir, which a worktree or a submodule keeps outside it.
        writable=$workdir
        gitdir=
        if toplevel=$(git -C "$workdir" rev-parse --show-toplevel 2>/dev/null); then
            writable=$toplevel
            gitdir=$(git -C "$workdir" rev-parse --path-format=absolute --git-common-dir)
        fi
        refuse "$writable"
        mounts+=(--bind "$writable" "$writable")
        [ -n "$gitdir" ] && mounts+=(--bind "$gitdir" "$gitdir")
    else
        workdir=/work
        mounts+=(--tmpfs /work)
        declare -A seen=()
        for d in "${write_dirs[@]}"; do
            d=$(realpath -e "$d") || exit 64
            refuse "$d"
            name=$(basename "$d")
            if [ -n "${seen[$name]:-}" ]; then
                echo "refusing: $d and ${seen[$name]} are both /work/$name" >&2
                exit 64
            fi
            seen[$name]=$d
            mounts+=(--bind "$d" "/work/$name")
            # A worktree or a submodule keeps its git dir outside it, at a host
            # path.
            if [ "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" = "$d" ]; then
                gitdir=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir)
                mounts+=(--bind "$gitdir" "$gitdir")
            fi
        done
    fi
    # A socket seen through the overlay refuses connections: the agent's
    # directory is bound on top, so git over ssh can use the host keys.
    if [ -S "${SSH_AUTH_SOCK:-}" ]; then
        agent_dir=$(dirname "$SSH_AUTH_SOCK")
        mounts+=(--ro-bind "$agent_dir" "$agent_dir")
    fi
    cdest="$cdir"
    trust "$home/.claude.json" "$workdir"
fi

for p in hooks settings.json plugins; do
    [ -e "$cdir/$p" ] && mounts+=(--ro-bind "$cdir/$p" "$cdest/$p")
done
# Claude writes in-use markers into the plugin cache. A throwaway overlay takes
# them and keeps the host copy untouched.
[ -d "$cdir/plugins/cache" ] && mounts+=(
    --overlay-src "$cdir/plugins/cache"
    --tmp-overlay "$cdest/plugins/cache"
)

if [ "${CLAUDE_SPEAK:-}" = 1 ]; then
    # Voice mode records through pipewire, the speak.sh Stop hook talks to
    # speech-dispatcher. Both sockets live in the host runtime dir.
    rundir=/run/user/$uid
    mounts+=(
        --setenv   XDG_RUNTIME_DIR "$rundir"
        --bind-try "$rundir/speech-dispatcher" "$rundir/speech-dispatcher"
        --bind-try "$rundir/pipewire-0" "$rundir/pipewire-0"
        --bind-try "$rundir/pulse" "$rundir/pulse"
    )
fi

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
