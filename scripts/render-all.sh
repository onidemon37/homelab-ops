#!/usr/bin/env bash
# Renders every Flux entrypoint and overlay with kustomize, mirroring the CI matrix.
# Single source of truth for Taskfile and Makefile targets.
#
# Usage: render-all.sh [atlantis|galactica|pegasus|all]

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

paths_for() {
  case "$1" in
    atlantis)
      printf '%s\n' \
        clusters/prod/atlantis \
        apps/overlays/prod/atlantis/infrastructure \
        apps/overlays/prod/atlantis/networking \
        apps/overlays/prod/atlantis/observability \
        apps/overlays/prod/atlantis/shared-services
      ;;
    galactica)
      printf '%s\n' \
        clusters/prod/galactica \
        apps/overlays/prod/galactica/infrastructure \
        apps/overlays/prod/galactica/cnpg \
        apps/overlays/prod/galactica/databases \
        apps/overlays/prod/galactica/networking \
        apps/overlays/prod/galactica/observability
      ;;
    pegasus)
      printf '%s\n' \
        clusters/non-prod/pegasus \
        apps/overlays/non-prod/pegasus/infrastructure \
        apps/overlays/non-prod/pegasus/databases \
        apps/overlays/non-prod/pegasus/networking \
        apps/overlays/non-prod/pegasus/observability
      ;;
    *)
      echo "Unknown cluster: $1 (expected atlantis, galactica, pegasus or all)" >&2
      return 2
      ;;
  esac
}

target="${1:-all}"
if [[ "$target" == "all" ]]; then
  clusters="atlantis galactica pegasus"
else
  paths_for "$target" >/dev/null
  clusters="$target"
fi

status=0
for cluster in $clusters; do
  while IFS= read -r path; do
    if kustomize build "$path" >/dev/null; then
      echo "ok    $path"
    else
      echo "FAIL  $path" >&2
      status=1
    fi
  done < <(paths_for "$cluster")
done
exit $status
