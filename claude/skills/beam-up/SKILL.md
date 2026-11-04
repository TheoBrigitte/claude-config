---
name: beam-up
description: >
  Run Claude Code sessions in disposable remote Kubernetes instances ("beam"): copy the current session to a remote pod, start an empty remote session, and list or destroy remote instances.
  TRIGGER when: the user says "beam me up" or "beam up", asks to continue this session remotely or in the cluster or while the laptop is closed, to start a remote Claude, or to list, attach to or destroy a remote instance.
  DO NOT TRIGGER when: the user asks about Claude Code on the web or cloud sessions, or is editing the beam scripts themselves.
allowed-tools: Bash
argument-hint: "[up | new | list | attach INSTANCE | destroy INSTANCE] [-n NAME] [--persistent]"
---

# Beam up

The scripts live in `~/projects/claude/bin`. They act on the current kube context. Each instance is the namespace `claude-theo-<instance>` with one pod. `~/projects/claude/CLAUDE_REMOTE.md` describes the design.

## Steps

1. Run `kubectl config current-context` and tell the user which cluster the instance goes to. On an auth or certificate error, ask the user to run `! tsh login --proxy=teleport.giantswarm.io`, then stop.
2. Run the script for the request:

| Request | Command |
|---|---|
| Copy this session to a remote instance (default) | `~/projects/claude/bin/beam-up.sh [-n NAME] [--persistent]` |
| Start an empty remote session | `~/projects/claude/bin/beam-up.sh --new [-n NAME] [--persistent]` |
| List instances | `~/projects/claude/bin/beam-list.sh` |
| Destroy an instance | `~/projects/claude/bin/beam-destroy.sh INSTANCE` |

3. Show the user the script's output. For `beam-up.sh`, the last line is the attach command.

## Rules

- **Switching this terminal.** Never run `beam-up-switch.sh` yourself: it kills this Claude. When the user wants this terminal to continue remotely, tell them to run `! ~/projects/claude/bin/beam-up-switch.sh [-n NAME] [--persistent] [--new]` themselves.
- **Attaching.** `beam-attach.sh` needs a terminal. Tell the user to run `~/projects/claude/bin/beam-attach.sh INSTANCE` in a terminal. Ctrl+Z detaches. After a pod restart, add `--push-credentials`.
- **Destroying.** Ask the user to confirm before `beam-destroy.sh`. It deletes the instance, its sessions and its home volume, including a `--persistent` one.
- **Copies.** A copy is a fork of this session at the moment of the copy. It doesn't follow later changes.
- **Interrupted call.** The copy ends with the `beam-up.sh` call that made it. The remote session shows that call as interrupted. Tell the user this is expected: they can type normally.
- **Names.** The instance name defaults to the session's short ID. If the instance exists, `beam-up.sh` fails: offer another `-n NAME`, or destroying the old instance.
- **Login.** `beam-up.sh` pushes the current claude.ai login and settings into the pod's memory. The login never touches disk in the pod.
