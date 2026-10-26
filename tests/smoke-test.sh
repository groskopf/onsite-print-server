#!/bin/bash
set -euo pipefail

base="${1:-http://localhost:8080}"
base="${base%/}"

# Pinned-release CI can select only apps available in those historical images.
read -r -a apps <<< "${SMOKE_APPS:-attendee checkin admin}"
for app in "${apps[@]}"; do
  [[ "$(curl --silent --show-error -o /dev/null -w '%{http_code}' "$base/$app")" == 308 ]]
  html="$(curl --fail --silent --show-error "$base/$app/")"
  asset="$(printf '%s\n' "$html" | grep -oE "src=\"/$app/assets/[^\"]+\\.js\"" | head -n 1 | cut -d '"' -f 2)"
  [[ -n "$asset" ]]
  curl --fail --silent --show-error -o /dev/null "$base$asset"
  [[ "$(curl --silent --show-error -o /dev/null -w '%{http_code}' "$base/$app/assets/missing.js")" == 404 ]]
  [[ "$(curl --fail --silent --show-error "$base/$app/nested/route")" == "$html" ]]
done

curl --fail --silent --show-error "$base/api/v2/health" | grep -q '"status":"ok"'
curl --fail --silent --show-error "$base/api/v2/docs" | grep -q 'Swagger UI'
curl --fail --silent --show-error "$base/api/v2/openapi.json" | grep -q '/api/v2/health'
echo "Production routing smoke tests passed: $base"
