#!/usr/bin/env bash
# Destroy a remote instance, in the current kube context.
#
# Usage: beam-destroy.sh INSTANCE
#
# Deletes the namespace claude-theo-INSTANCE: its pod, PVC and in-memory login.
set -euo pipefail

instance=${1:?Usage: beam-destroy.sh INSTANCE}
kubectl delete ns "claude-theo-$instance"
