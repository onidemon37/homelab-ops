#!/usr/bin/env bash
# Mints a short-lived (1h) GitHub App installation token and exports it as
# TF_VAR_git_token, for use by terraform/{non-prod,prod} before `tofu apply`.
#
# Must be SOURCED, not executed, so the export reaches your current shell:
#   source scripts/get-git-app-token.sh <app-id> <installation-id> <path-to-pem>
#
# Requires: openssl, curl, jq.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This script must be sourced, not executed: 'source ${0} 4942670 161669261 ~/Downloads/galactica-non-prod-flux.2026-09-14.private-key.pem'" >&2
  exit 1
fi

if [[ $# -ne 3 ]]; then
  echo "Usage: source ${BASH_SOURCE[0]} 4942670 161669261 ~/Downloads/galactica-non-prod-flux.2026-09-14.private-key.pem" >&2
  return 1
fi

APP_ID="$1"
INSTALLATION_ID="$2"
PEM_FILE="$3"

if [[ ! -r "$PEM_FILE" ]]; then
  echo "Private key is not readable: $PEM_FILE" >&2
  return 1
fi

now=$(date +%s)
iat=$((now - 60))
exp=$((now + 540)) # max 10 min

header=$(printf '{"alg":"RS256","typ":"JWT"}' | openssl base64 -A | tr '+/' '-_' | tr -d '=')
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$iat" "$exp" "$APP_ID" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
unsigned="${header}.${payload}"
if ! signature=$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$PEM_FILE" | openssl base64 -A | tr '+/' '-_' | tr -d '='); then
  echo "Failed to sign the GitHub App JWT with: $PEM_FILE" >&2
  return 1
fi
jwt="${unsigned}.${signature}"

response=$(curl -sS -X POST \
  -H "Authorization: Bearer $jwt" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens") || {
  echo "Failed to contact the GitHub API." >&2
  return 1
}

TF_VAR_git_token=$(printf '%s' "$response" | jq -r '.token // empty')

if [[ -z "$TF_VAR_git_token" || "$TF_VAR_git_token" == "null" ]]; then
  message=$(printf '%s' "$response" | jq -r '.message // "unknown GitHub API error"')
  echo "Failed to mint an installation token: $message" >&2
  return 1
fi

export TF_VAR_git_token
echo "TF_VAR_git_token exported (expires in ~1h)."
