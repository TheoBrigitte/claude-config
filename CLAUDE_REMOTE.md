# Remote Claude

Run Claude Code in a Kubernetes pod. It keeps working while the laptop is closed. Attach from a terminal like a local session.

## Status

Working on graveler, 2026-11-04.

### Pieces

- An instance is a namespace `claude-theo-<instance>` with one pod, `claude-0`. The namespace has the label `beam.giantswarm.io/instance=<instance>`. Instances are disposable: each has its own home volume and login.
- `k8s/claude-graveler/manifests.yaml`: namespace, ConfigMap `claude-scripts`, StatefulSet `claude`, 5Gi `emptyDir` home volume at `/home/node` on the node's disk, 64Mi memory volume at `/run/claude`. `INSTANCE` is the placeholder for the instance name. Lines ending in `# ephemeral` hold the `emptyDir`. Lines starting with `#persistent ` hold a 20Gi gp3 `volumeClaimTemplate`. `--persistent` deletes the first and uncomments the second.
- `bin/beam-up.sh [-n INSTANCE] [--persistent] [--new | SESSION_ID]`: creates an instance and starts a remote background session in it. With SESSION_ID, it copies the session transcript and resumes it. With `--new`, it starts an empty session. The instance defaults to the session's short ID, or to 8 random hex characters with `--new`. An existing instance makes it fail: destroy it or pick another `-n`. Every run pushes the local settings, login and `.claude.json`. The login and `.claude.json` go into the pod's memory.
- `bin/beam-attach.sh [--push-credentials] INSTANCE [ID]`: attaches to a remote background session. Without ID it opens the session `beam-up.sh` started, from `~/.beam-session` in the pod. `--push-credentials` first pushes the local login and settings into memory and resumes the session from its transcript when the daemon doesn't run it.
- `bin/beam-up-switch.sh [-n INSTANCE] [--persistent] [--new | SESSION_ID]`: runs `beam-up.sh` with the same arguments, then replaces the local tmux pane with the attach.
- `bin/beam-list.sh`: lists the instances and their pods.
- `bin/beam-destroy.sh INSTANCE`: deletes the instance namespace, with its pod, home volume and login. A gp3 PV goes with it: its reclaim policy is Delete.
- `bin/beam-lib.sh`: builds the login and settings tar for `beam-up.sh` and `beam-attach.sh`.
- `images/claude/Dockerfile`: the instance image, `docker.io/theo01/beam-claude:<claude version>`.
- `bin/beam-remote-copy.sh`: runs in the pod. `beam-up.sh` sends its content with `kubectl exec ... bash -c`, in one exec. Data goes over stdin as one tar stream. Each member carries its destination path: the login goes to `/run/claude/config`, the settings and transcript to the home volume.

All scripts use the current kube context.

### Pod

- Image `docker.io/theo01/beam-claude:2.1.317`, public, 158 MB compressed. Alpine 3.24, the native Claude binary at `/usr/local/bin/claude`, bash, jq, procps and GNU coreutils, tar, grep, sed, gawk, findutils, diffutils and which. No node, curl, git or python3.
- User 1000, restricted pod security. graveler's Kyverno enforces it.
- PID 1 runs `start.sh` from the ConfigMap. The pod installs nothing at boot.
- `CLAUDE_CONFIG_DIR=/run/claude/config`, on the memory volume. It holds `.credentials.json`, `.claude.json` and the daemon state.
- Symlinks in the config dir point to the home volume: `projects`, `settings.json`, `CLAUDE.md`, `keybindings.json`, `agents`, `skills`, `plugins`.
- PID 1 supervises `claude daemon run` and reaps orphaned processes. The daemon starts without a login and finds it when `beam-up.sh` pushes it.
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
- **Tools are missing.** The image has no git, curl, go, gh, kubectl, python3 or `claude-statusline`.
- **A plugin hook fails.** A `SessionStart:resume` hook from a plugin fails with `env: 'python3': No such file or directory`. The session still starts.
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

### Timings

Measured on graveler, 2026-11-04, image cached on the node:

| Step | Time |
|---|---|
| `beam-up.sh SESSION_ID` | 6.9 s |
| `beam-up.sh --new` | 6.7 s |
| `beam-up.sh --persistent SESSION_ID` | 13.9 s |
| `beam-attach.sh` to the prompt | 1.1-1.3 s |
| `beam-attach.sh --push-credentials` after a restart | 5.3 s |
| Pod restart, `--persistent` | 38 s to Ready |
| `beam-destroy.sh` | ~60 s, waits for the namespace to go |

- The first pull of the image on a node adds 4.5-4.8 s from Docker Hub.
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

The image exists: `images/claude/Dockerfile`, pushed to Docker Hub. Rebuild and push with `docker build -t docker.io/theo01/beam-claude:<version> images/claude && docker push docker.io/theo01/beam-claude:<version>`, then update the manifest.

Still to add:

- Shell tools: zsh, git, yq, ripgrep, fd, curl.
- Languages: go, node with npx, uv with uvx. The stdio MCP servers use npx and uvx.
- Kubernetes: kubectl, helm, flux, tsh, kubectl-gs, opsctl, devctl.
- GitHub: gh.
- Claude: Claude Code pinned, `claude-statusline`.
- python3, for plugin hooks.

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

Package the scripts as a skill, `beam-me-up`:

- `SKILL.md` tells Claude when to run each script: start, copy, switch, attach, stop, down.
- The scripts ship inside the skill folder.
- `/beam-me-up` runs the switch.

To test: when Claude runs the switch through its Bash tool, the switch kills that Claude mid tool call. The remote transcript then ends with a tool call without a result. Check that `--resume` handles this. If it doesn't, have the skill tell the user to run `! beam-up-switch` themselves.

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
