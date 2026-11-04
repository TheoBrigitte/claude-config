# Remote Claude

Run Claude Code in a Kubernetes pod. It keeps working while the laptop is closed. Attach from a terminal like a local session.

## Status

Working on graveler, 2026-11-04.

### Pieces

- An instance is a namespace `claude-theo-<instance>` with one pod, `claude-0`. The namespace has the label `beam.giantswarm.io/instance=<instance>`. Instances are disposable: each has its own home volume and login.
- `k8s/claude-graveler/manifests.yaml`: namespace, StatefulSet `claude`, 5Gi `emptyDir` home volume at `/home/node` on the node's disk, 64Mi memory volume at `/run/claude`. `INSTANCE` is the placeholder for the instance name. Lines ending in `# ephemeral` hold the `emptyDir`. Lines starting with `#persistent ` hold a 20Gi gp3 `volumeClaimTemplate`. `--persistent` deletes the first and uncomments the second.
- `bin/beam-up.sh [-n INSTANCE] [--persistent] [--new | SESSION_ID]`: creates an instance and starts a remote background session in it. With SESSION_ID, it copies the session transcript and resumes it. With `--new`, it starts an empty session. The instance defaults to the session's short ID, or to 8 random hex characters with `--new`. An existing instance makes it fail: destroy it or pick another `-n`. Every run pushes the local settings, login and `.claude.json`. The login and `.claude.json` go into the pod's memory.
- `bin/beam-attach.sh [--push-credentials] INSTANCE [ID]`: attaches to a remote background session. Without ID it opens the session `beam-up.sh` started, from `~/.beam-session` in the pod. `--push-credentials` first pushes the local login and settings into memory and resumes the session from its transcript when the daemon doesn't run it.
- `bin/beam-up-switch.sh [-n INSTANCE] [--persistent] [--new | SESSION_ID]`: runs `beam-up.sh` with the same arguments, then replaces the local tmux pane with the attach.
- `bin/beam-list.sh`: lists the instances and their pods.
- `bin/beam-destroy.sh INSTANCE`: deletes the instance namespace, with its pod, home volume and login. A gp3 PV goes with it: its reclaim policy is Delete.
- `bin/beam-lib.sh`: builds the login and settings tar for `beam-up.sh` and `beam-attach.sh`.
- `images/claude/Dockerfile`: the instance image, `docker.io/theo01/beam-claude:<claude version>-<build>`. Bump the build suffix on any image change. Reset it to 1 when the Claude version changes.
- `images/claude/start.sh`: the image's default command, at `/usr/local/bin/start.sh`. tini runs it.
- `bin/beam-remote-copy.sh`: runs in the pod. `beam-up.sh` sends its content with `kubectl exec ... bash -c`, in one exec. Data goes over stdin as one tar stream. Each member carries its destination path: the login goes to `/run/claude/config`, the settings and transcript to the home volume.

All scripts use the current kube context.

### Pod

- Image `docker.io/theo01/beam-claude:2.1.317-3`, public, 179 MB compressed. Alpine 3.24, tini, the native Claude binary at `/usr/local/bin/claude`, bash, jq, git, curl, python3, procps and GNU coreutils, tar, grep, sed, gawk, findutils, diffutils and which. No node.
- The image sets `SHELL=/bin/bash`, `LANG=C.UTF-8`, `LC_ALL=C.UTF-8`, `CLAUDE_CONFIG_DIR=/run/claude/config` and `DISABLE_AUTOUPDATER=1`. `kubectl exec` sessions see them.
- User 1000, restricted pod security. graveler's Kyverno enforces it.
- PID 1 is tini. It runs the image's `start.sh`, forwards signals and reaps orphaned processes. The pod installs nothing at boot.
- `start.sh` creates the config dir and the symlinks, then execs `claude daemon run`. The daemon starts without a login and finds it when `beam-up.sh` pushes it.
- `CLAUDE_CONFIG_DIR=/run/claude/config`, on the memory volume. It holds `.credentials.json`, `.claude.json` and the daemon state.
- Symlinks in the config dir point to the home volume: `projects`, `settings.json`, `CLAUDE.md`, `keybindings.json`, `agents`, `skills`, `plugins`.
- When the daemon exits, the container exits and the kubelet restarts it in ~1 s. The memory and home volumes stay. The background sessions stop. See Restart.
- Pod deletion takes ~2 s: the daemon exits on SIGTERM.
- Sessions are Claude background sessions: `claude --bg --resume <id>` starts one, `claude attach <id>` opens it. The short ID is the first 8 characters of the session ID.
- `claude --bg` picks its own session ID. It ignores `--session-id` with a warning. `claude --bg --resume <id>` without a transcript exits on attach. `--new` runs plain `claude --bg` and reads the short ID from its output.
- `claude attach` matches a name only when it is not 8 hex characters.
- Detach: Ctrl+Z. ← opens agent view. A dropped connection leaves the session running.
- Claude runs in `/home/node/work`. Its project folder is `-home-node-work`.
- Auth: the laptop's claude.ai login, shared with the pod and held in memory. `beam-up.sh` pushes the current copy. Remote Control (`/rc`) works.
- Settings: copied from the laptop when the instance is created. `beam-up.sh` removes the hooks.
- A pod restart wipes the memory volume and stops the background sessions. See Restart.

### Known issues

- **Paths differ.** Transcripts refer to `/home/theo/...`. The pod uses `/home/node/work`.
- **Tools are missing.** The image has no go, gh, kubectl or `claude-statusline`.
- **Registry policy.** graveler's `restrict-image-registries` policy flags images outside `gsoci.azurecr.io/giantswarm`. It runs in Audit mode, so pods still start.
- **MCP servers don't connect.** Their configs and env secrets stay on the laptop.
- **Claude is pinned.** The image pins v2.1.317 and sets `DISABLE_AUTOUPDATER=1`. Upgrade by rebuilding the image.
- **Stale attach clients.** A dropped connection leaves a `claude attach` process in the pod until the kubelet idle timeout. `beam-attach.sh` kills them before attaching.
- **Shared login refresh.** The pod's daemon refreshes the OAuth token on its own schedule. If a refresh replaces the refresh token, the laptop's copy may stop working until the next push or a local `/login`.

### Restart

Tested on a `--persistent` instance with `kubectl delete pod claude-0`. The pod was Ready again after 38 s.

- Kept, on the PVC: transcripts, settings without hooks, `~/.beam-session`.
- Lost, in memory: `.credentials.json`, the full `.claude.json` with the trust of `~/work`, the background sessions. Plain `beam-attach.sh` fails: `No job matching '<short>'`.
- `bin/beam-attach.sh --push-credentials INSTANCE` pushes the login, resumes the session and attaches. It reached the copied conversation in 5.3 s. On a running instance it starts no second session.

On an `emptyDir` instance a restart also loses the home volume.

Daemon exit, tested by killing `claude daemon run`. The container restarted once, Ready in ~1 s.

- Kept, in memory: `.credentials.json`, `.claude.json`.
- Lost: the background sessions.
- `bin/beam-attach.sh --push-credentials INSTANCE` resumes the session and attaches. It reached the copied conversation in 5.3 s.
- A `--new` session without a message has no transcript. `--push-credentials` then fails: `No single transcript for session <short>`.

### Timings

Measured on graveler, 2026-11-04, image cached on the node:

| Step | Time |
|---|---|
| `beam-up.sh SESSION_ID` | 6.9 s |
| `beam-up.sh --new` | 6.0-6.1 s |
| `beam-up.sh --persistent SESSION_ID` | 13.9 s |
| `beam-attach.sh` to the prompt | 1.3 s |
| `beam-attach.sh --push-credentials` after a restart | 5.3 s |
| Pod restart, `--persistent` | 38 s to Ready |
| `kubectl delete pod claude-0`, `emptyDir` | 1.8 s, Ready 1.0 s later |
| Daemon exit to container Ready | ~1 s |
| `beam-destroy.sh` | 0.4 s, the namespace is gone after 16 s |

- The first pull of the image on a node adds 4.5-8.4 s from Docker Hub.
- An `emptyDir` home volume is ready in ~1.7 s. A fresh gp3 PVC takes 8.7-12.9 s.
- A full cluster adds the time Karpenter needs for a new node: 135 s in one run.

## Next

### 1. Paths

Mirror the laptop layout in the pod:

- Run the pod with `HOME=/home/theo` and the home volume mounted there.
- Put working directories at their laptop paths, for example `/home/theo/projects/claude`.
- The project folder then matches: `-home-theo-projects-claude`. `beam-up.sh` no longer rewrites it.
- Paths in transcripts, CLAUDE.md, settings and hooks resolve unchanged.
- `beam-up.sh` places the transcript under the project folder of its recorded `cwd`.

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

The image exists: `images/claude/Dockerfile`, pushed to Docker Hub. Rebuild and push with `docker build -t docker.io/theo01/beam-claude:<tag> images/claude && docker push docker.io/theo01/beam-claude:<tag>`, then update the manifest. The tag is `<claude version>-<build>`. Bump the build suffix on any image change. Reset it to 1 when the Claude version changes. Never overwrite a pushed tag: nodes keep the cached image.

Still to add:

- Shell tools: zsh, yq, ripgrep, fd.
- Languages: go, node with npx, uv with uvx. The stdio MCP servers use npx and uvx.
- Kubernetes: kubectl, helm, flux, tsh, kubectl-gs, opsctl, devctl.
- GitHub: gh.
- Claude: Claude Code pinned, `claude-statusline`.

Later: build in CI and push to `gsoci.azurecr.io`, which the registry policy allows.

Existing images, checked on 2026-11-03:

| Image | Claude | Gap |
|---|---|---|
| `gsoci.azurecr.io/giantswarm/kagent/claude-harness:1.30.0` | 2.1.303 | Alpine, root, no node, ships a kagent CLAUDE.md |
| `gsoci.azurecr.io/giantswarm/klaus:1.0.37` | 2.1.311 | No curl, git, jq or gh |
| `gsoci.azurecr.io/giantswarm/claude-code-ci` | 2.1.36 | Too old for `claude daemon` |

None fits. Public images such as `docker/sandbox-templates:claude-code` either lag the Claude version, run as root, or install Claude under `$HOME`. For gsoci, use https://github.com/giantswarm/custom-container-images with `claude-code-ci` as the template.

The home volume keeps `$HOME` only. Tools live in the image.

### 4. Skill

Done: `claude/skills/beam-up/SKILL.md`. It runs `beam-up.sh`, `beam-list.sh` and `beam-destroy.sh`, and asks before destroying. It never runs `beam-up-switch.sh` (that kills the calling Claude) or `beam-attach.sh` (needs a terminal): it tells the user the command instead.

A copy made from Claude's Bash tool ends with that tool call. The remote session shows it as interrupted and continues normally. Tested 2026-11-04.

### 5. Tear down

Add `beam-stop.sh`:

- Delete the namespace, as `beam-destroy.sh` does. The home volume and the login go with the pod.
- Before deleting, offer a beam down of the running session.
- After deleting, verify that the PV is gone.

### 6. Secrets

#### Requirement

Secrets and logins never touch disk. That covers:

- the claude.ai login;
- MCP OAuth tokens;
- MCP env secrets: GitHub, Grafana, PagerDuty, context7, jina, n8n;
- any other token.

They live in pod memory only. They also stay out of Kubernetes Secrets: those persist in etcd.

#### Design

- **Memory volume.** Mount an `emptyDir` with `medium: Memory` at `/run/claude`. It is tmpfs and disappears with the pod.
- **Config dir in memory.** Set `CLAUDE_CONFIG_DIR=/run/claude/config`. Claude then writes `.credentials.json` into tmpfs, including atomic rewrites on token refresh.
- **Non-secret parts by symlink.** In the tmpfs config dir, symlink these to the home volume:
  - `projects/`
  - `todos/`
  - `settings.json`
  - `CLAUDE.md`
  - `agents/`
  - `skills/`
  - `plugins/`

  Session history survives a restart. Credentials don't.
- **Push at start.** `beam-up.sh` streams the credentials and an env file over `kubectl exec` stdin, straight into `/run/claude`. Nothing is written on the laptop or in the pod outside tmpfs.
- **Env secrets from 1Password.** `beam-up.sh` runs `op inject` locally with `op://` refs. The daemon sources `/run/claude/env` before it starts.
- **Wait for secrets.** The PID 1 supervisor starts Claude only after `/run/claude/config/.credentials.json` exists.
- **Restart.** A pod restart wipes tmpfs. See Status, Restart.

#### To verify

- Claude writes no secret outside `CLAUDE_CONFIG_DIR`. Check `.claude.json` (it moves into the config dir with `CLAUDE_CONFIG_DIR`), `~/.cache` and `~/.config`.
- MCP servers write no tokens to disk. Check `npx` and `uvx` caches, `~/.config/gh` and `~/.kube`. Point their config dirs at tmpfs.
- Transcripts stay clean. Tool output can contain tokens, and transcripts live on the home volume. Keep secrets out of commands and outputs, and check for a redaction option.
- The nodes have no swap. tmpfs pages could otherwise reach disk.
- The tmpfs size limit covers the files: set `sizeLimit` on the `emptyDir`.

#### Further hardening

| Control | Effect |
|---|---|
| Scoped, short-lived tokens per remote session | Limits the impact of a leak. |
| Egress NetworkPolicy allowlist: Anthropic, GitHub, Slack, the MCP hosts | Blocks exfiltration to arbitrary hosts. |
| Kyverno policy: exec into the namespace only for your identity | Stops casual access. Cluster admins can still bypass it. |
| A cluster or VM that only you administer | Cluster admins and node root can read pod memory. This removes them. |

#### Done

- Memory volume, config dir in memory, symlinks to the home volume, push at copy.
- Verified: `.credentials.json` and `.claude.json` exist only on tmpfs. `find /home/node` finds neither.

#### Open

- Env secrets from 1Password.
- The checks under "To verify".

### 7. Beam down

The reverse of the copy:

- `beam-down.sh`: tar the remote transcript back to the local project folder.
- `beam-down-switch.sh`: stop the remote background session, copy the transcript back, and replace the local tmux pane with `claude --resume <id>`.
- Bring the working directories back: git pull, tar or sync, the same method as item 2.

Path mirroring from item 1 makes the transcript valid on both sides.

Conflict: if both sides continued after the fork, the transcripts diverge. Beam down replaces the local copy. Keep a backup of the replaced transcript.
