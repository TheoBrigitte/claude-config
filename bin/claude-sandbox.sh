#!/usr/bin/env bash
# stolen from glitchcrab https://gigantic.slack.com/archives/C05DCHUKTFH/p1773071560428739?thread_ts=1773071457.451679&cid=C05DCHUKTFH

set -eu

# Create workdir
SESSION_ID="$(uuidgen)"
WORKDIR="${CLAUDE_CONFIG_SANDBOX_DIR%/}/${SESSION_ID}"
mkdir "$WORKDIR"

# Create claude config directory
CLAUDE_CONFIG_DIR="$WORKDIR/.claude_config"
mkdir "$CLAUDE_CONFIG_DIR"

# Copy claude configuration to workdir, excluding projects and debug directories which may contain large files and are not needed for the session
rsync -aP --quiet "$HOME/.claude/" "$CLAUDE_CONFIG_DIR/" \
  --exclude "projects" \
  --exclude "debug"
cp "$HOME/.claude.json" "$WORKDIR/.claude.json"

echo "WORKDIR: $WORKDIR" 1>&2

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
    --ro-bind "$HOME/.local" "$HOME/.local" \
    --bind "$CLAUDE_CONFIG_DIR" "$HOME/.claude" \
    --bind "$WORKDIR/.claude.json" "$HOME/.claude.json" \
    --bind "$WORKDIR" "$WORKDIR" \
    --tmpfs /tmp \
    --proc /proc \
    --dev /dev \
    --share-net \
    --unshare-pid \
    --die-with-parent \
    --chdir "$WORKDIR" \
    /usr/bin/claude --session-id "$SESSION_ID" "$@" # start Claude and pass all arguments through

### Alternative from: https://github.com/giantswarm/rfc/pull/135/changes

#bwrap \
#    --unshare-user-try \
#    --uid $(id -u) \
#    --gid $(id -g) \
#    --ro-bind /usr /usr \
#    --ro-bind /lib /lib \
#    --ro-bind /lib64 /lib64 \
#    --ro-bind /bin /bin \
#    --ro-bind /etc/resolv.conf /etc/resolv.conf \
#    --ro-bind /etc/hosts /etc/hosts \
#    --ro-bind /etc/ssl /etc/ssl \
#    --ro-bind /etc/alternatives /etc/alternatives \
#    --ro-bind "$temp_passwd" /etc/passwd \
#    --ro-bind /etc/group /etc/group \
#    --ro-bind "$HOME/.gitconfig" "$HOME/.gitconfig" \
#    --ro-bind "$HOME/.1password" "$HOME/.1password" \
#    --ro-bind "$HOME/.nvm" "$HOME/.nvm" \
#    --ro-bind "$HOME/.local" "$HOME/.local" \
#    --ro-bind "$HOME/.ssh" "$HOME/.ssh" \
#    --ro-bind "$HOME/.config/gh" "$HOME/.config/gh" \
#    --dir "$XDG_RUNTIME_DIR" \
#    --ro-bind "$HOME/bin" "$HOME/bin" \
#    --bind "$PROJECT_DIR" "$PROJECT_DIR" \
#    --bind "$HOME/.claude" "$HOME/.claude" \
#    --bind "$HOME/.claude.json" "$HOME/.claude.json" \
#    --bind "$HOME/.local/share/claude" "$HOME/.local/share/claude" \
#    --bind "$HOME/.m2" "$HOME/.m2" \
#    --bind "$HOME/.gradle" "$HOME/.gradle" \
#    --bind "$HOME/go" "$HOME/go" \
#    --bind "$HOME/.npm" "$HOME/.npm" \
#    --bind "$HOME/.java" "$HOME/.java" \
#    --bind "$HOME/.cache/pip" "$HOME/.cache/pip" \
#    --bind "$HOME/.cache/helm" "$HOME/.cache/helm" \
#    --bind "$HOME/.cache/go" "$HOME/.cache/go" \
#    --bind "$HOME/.cache/go-build" "$HOME/.cache/go-build" \
#    --bind "$SSH_AUTH_SOCK" "$SSH_AUTH_SOCK" \
#    --setenv "OP_SERVICE_ACCOUNT_TOKEN" "$account_token" \
#    --setenv "GH_TOKEN" "op://$vault/OPSCTL_GITHUB_TOKEN/password" \
#    --setenv "GITHUB_TOKEN" "op://$vault/OPSCTL_GITHUB_TOKEN/password" \
#    --setenv "OPSCTL_GITHUB_TOKEN" "op://$vault/OPSCTL_GITHUB_TOKEN/password" \
#    --setenv "SSH_AUTH_SOCK" "$SSH_AUTH_SOCK" \
#    --setenv "SSH_ASKPASS" "$SSH_ASKPASS" \
#    --tmpfs /tmp \
#    --proc /proc \
#    --dev /dev \
#    --share-net \
#    --unshare-pid \
#    --die-with-parent \
#    --setenv IS_SANDBOX 1 \
#    --chdir "$PROJECT_DIR" \
#    --ro-bind /dev/null "$PROJECT_DIR/.env" \
#    --ro-bind /dev/null "$PROJECT_DIR/.env.local" \
#    --ro-bind /dev/null "$PROJECT_DIR/.env.production" \
#    "$(command -v claude)" --dangerously-skip-permissions
