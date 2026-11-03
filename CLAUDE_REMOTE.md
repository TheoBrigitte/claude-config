# Remote Claude

Run Claude Code in a Kubernetes pod. It keeps working while the laptop is closed. Attach from a terminal like a local session.

## Status

Working on graveler, 2026-11-03.

### Pieces

- `k8s/claude-graveler/manifests.yaml`: namespace `claude-theo`, ConfigMap `claude-scripts`, StatefulSet `claude`, 20Gi gp3 PVC at `/home/node`.
- `bin/beam-start.sh`: applies the manifests and waits for the tmux session. On first run it copies the local login and settings into the pod.
- `bin/beam-attach.sh`: attaches to the pod's tmux session.
- `bin/beam-copy.sh`: copies a session transcript to the pod.
- `bin/beam-copy-switch.sh`: copies a session, resumes it in the pod, and replaces the local tmux pane with the attach.

All scripts use the current kube context.

### Pod

- Image `node:22-bookworm`, user 1000, restricted pod security. graveler's Kyverno enforces it.
- PID 1 runs `start.sh` from the ConfigMap. It installs micromamba, tmux and Claude Code onto the PVC once.
- PID 1 then supervises the tmux session `main`. It recreates the session if it dies and reaps orphaned processes.
- tmux prefix: `Ctrl+A`. Detach: `Ctrl+A d`.
- Claude runs in `/home/node/work`. Its project folder is `-home-node-work`.
- Auth: the copied claude.ai login in `.credentials.json`, on the PVC. Remote Control (`/rc`) works. This breaks the secrets requirement in item 6.
- Settings: copied from the laptop. `beam-start.sh` removes the hooks.

### Known issues

- **Paths differ.** Transcripts refer to `/home/theo/...`. The pod uses `/home/node/work`.
- **Tools are missing.** The pod has bash, git, node, curl, tmux and Claude. It has no jq, go, gh, kubectl or `claude-statusline`.
- **MCP servers don't connect.** Their configs and env secrets stay on the laptop.
- **Claude is pinned.** `DISABLE_AUTOUPDATER=1` from the settings pins v2.1.317. Upgrade with `claude update` in the pod.
- **Errors are unclear when the pod is missing.** `beam-copy.sh` prints `tar: Wrote only 4096 of 10240 bytes`. It should check for the namespace and pod first.

## Next

### 1. Paths

Mirror the laptop layout in the pod:

- Run the pod with `HOME=/home/theo` and the PVC mounted there.
- Put working directories at their laptop paths, for example `/home/theo/projects/claude`.
- The project folder then matches: `-home-theo-projects-claude`. `beam-copy.sh` no longer rewrites it.
- Paths in transcripts, CLAUDE.md, settings and hooks resolve unchanged.
- `beam-copy.sh` places the transcript under the project folder of its recorded `cwd`.

The UID stays 1000 on both sides.

### 2. Working directories

Copy the session's directories along with the transcript:

- The working directory, from the transcript's `cwd` field.
- Write directories:
  - claudy: `--write-dir`.
  - Native Claude: `--add-dir` and `/add-dir`, stored as `permissions.additionalDirectories`.
- Read directories: a new `--read-dir` flag. In the pod they become read-only, with `chmod -R a-w` or a read-only volume.

Discover the directories from the transcript and the settings. That works the same for claudy and native Claude. Keep explicit flags as overrides.

Transfer options:

| Method | Fit |
|---|---|
| tar over `kubectl exec` | One-shot snapshot. Already used for transcripts. |
| git: push a branch, clone in the pod | Repos only. Keeps history. Needs a GitHub token in the pod. |
| mutagen or rsync over `kubectl exec` | Two-way sync. Supports beam down. |

Size: skip `.git/objects` caches, `node_modules` and build output, or respect `.gitignore`.

### 3. Tools

Build an image to replace the install-at-boot setup:

- Base: Debian bookworm.
- Shell tools: bash, zsh, tmux, git, jq, yq, ripgrep, fd, curl.
- Languages: go, node with npx, uv with uvx. The stdio MCP servers use npx and uvx.
- Kubernetes: kubectl, helm, flux, tsh, kubectl-gs, opsctl, devctl.
- GitHub: gh.
- Claude: Claude Code pinned, `claude-statusline`.
- User 1000, no setuid binaries. Restricted pod security requires both.

Build in CI and push to `gsoci.azurecr.io` or `gsociprivate.azurecr.io`. Pin the tag in the StatefulSet.

The PVC keeps `$HOME` only. Tools live in the image.

### 4. Skill

Package the scripts as a skill, `beam-me-up`:

- `SKILL.md` tells Claude when to run each script: start, copy, switch, attach, stop, down.
- The scripts ship inside the skill folder.
- `/beam-me-up` runs the switch.

To test: when Claude runs the switch through its Bash tool, the switch kills that Claude mid tool call. The remote transcript then ends with a tool call without a result. Check that `--resume` handles this. If it doesn't, have the skill tell the user to run `! beam-copy-switch` themselves.

### 5. Tear down

Add `beam-stop.sh`:

- `--pause`: scale the StatefulSet to 0. The PVC stays. `beam-start.sh` resumes.
- Default: delete the namespace. The gp3 reclaim policy is Delete, so the PVC goes with it.
- Before deleting, offer a beam down of the running session.
- After deleting, verify that the PV is gone.

### 6. Secrets

#### Requirement

Secrets and logins never touch a PVC. That covers:

- the claude.ai login;
- MCP OAuth tokens;
- MCP env secrets: GitHub, Grafana, PagerDuty, context7, jina, n8n;
- any other token.

They live in pod memory only. They also stay out of Kubernetes Secrets: those persist in etcd.

#### Design

- **Memory volume.** Mount an `emptyDir` with `medium: Memory` at `/run/claude`. It is tmpfs and disappears with the pod.
- **Config dir in memory.** Set `CLAUDE_CONFIG_DIR=/run/claude/config`. Claude then writes `.credentials.json` into tmpfs, including atomic rewrites on token refresh.
- **Persistent parts by symlink.** In the tmpfs config dir, symlink these to the PVC:
  - `projects/`
  - `todos/`
  - `settings.json`
  - `CLAUDE.md`
  - `agents/`
  - `skills/`
  - `plugins/`

  Session history survives a restart. Credentials don't.
- **Push at start.** `beam-start.sh` streams the credentials and an env file over `kubectl exec` stdin, straight into `/run/claude`. Nothing is written on the laptop or in the pod outside tmpfs.
- **Env secrets from 1Password.** `beam-start.sh` runs `op inject` locally with `op://` refs. The tmux session sources `/run/claude/env`.
- **Wait for secrets.** The PID 1 supervisor starts Claude only after `/run/claude/config/.credentials.json` exists.
- **Restart.** A pod restart wipes tmpfs, and Claude waits until the next `beam-start.sh` push.

#### To verify

- Claude writes no secret outside `CLAUDE_CONFIG_DIR`. Check `.claude.json` (it moves into the config dir with `CLAUDE_CONFIG_DIR`), `~/.cache` and `~/.config`.
- MCP servers write no tokens to the PVC. Check `npx` and `uvx` caches, `~/.config/gh` and `~/.kube`. Point their config dirs at tmpfs.
- Transcripts stay clean. Tool output can contain tokens, and transcripts live on the PVC. Keep secrets out of commands and outputs, and check for a redaction option.
- The nodes have no swap. tmpfs pages could otherwise reach disk.
- The tmpfs size limit covers the files: set `sizeLimit` on the `emptyDir`.

#### Further hardening

| Control | Effect |
|---|---|
| Separate logins in the pod: `/login`, `/mcp` auth | No refresh token shared with the laptop. A refresh on one side can't log the other out. |
| Scoped, short-lived tokens per remote session | Limits the impact of a leak. |
| Egress NetworkPolicy allowlist: Anthropic, GitHub, Slack, the MCP hosts | Blocks exfiltration to arbitrary hosts. |
| Kyverno policy: exec into the namespace only for your identity | Stops casual access. Cluster admins can still bypass it. |
| A cluster or VM that only you administer | Cluster admins and node root can read pod memory. This removes them. |

#### Current gap

`beam-start.sh` copies `.credentials.json` onto the PVC. It holds the claude.ai login and 12 MCP OAuth entries. The design above replaces that copy.

### 7. Beam down

The reverse of the copy:

- `beam-down.sh`: tar the remote transcript back to the local project folder.
- `beam-down-switch.sh`: the copy, then replace the local tmux pane with `claude --resume <id>`. Kill the remote pane's Claude.
- Bring the working directories back: git pull, tar or sync, the same method as item 2.

Path mirroring from item 1 makes the transcript valid on both sides.

Conflict: if both sides continued after the fork, the transcripts diverge. Beam down replaces the local copy. Keep a backup of the replaced transcript.
