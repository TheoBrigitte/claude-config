#!/usr/bin/env bash
# List the remote instances and their pods, in the current kube context.
#
# Usage: beam-list.sh
set -euo pipefail

kubectl get pods -A -l beam.giantswarm.io/instance -L beam.giantswarm.io/instance
