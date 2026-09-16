#!/usr/bin/env bash
# Mints a short-lived GitHub App installation token (see get-git-app-token.sh) and
# applies it as the flux-system git credentials Secret on the current kube context.
#
# Usage: apply-git-secret.sh <app-id> <installation-id> <pem-file> [namespace] [secret-name]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_ID="${1:?Usage: ${0} <app-id> <installation-id> <pem-file> [namespace] [secret-name]}"
INSTALLATION_ID="${2:?Usage: ${0} <app-id> <installation-id> <pem-file> [namespace] [secret-name]}"
PEM_FILE="${3:?Usage: ${0} <app-id> <installation-id> <pem-file> [namespace] [secret-name]}"
NAMESPACE="${4:-flux-system}"
SECRET_NAME="${5:-flux-system}"

# shellcheck source=get-git-app-token.sh
source "${SCRIPT_DIR}/get-git-app-token.sh" "$APP_ID" "$INSTALLATION_ID" "$PEM_FILE"

kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=username=git \
  --from-literal=password="$TF_VAR_git_token" \
  --dry-run=client -o yaml \
  | kubectl apply -f -

echo "Applied Secret ${NAMESPACE}/${SECRET_NAME} (token valid ~1h)."
