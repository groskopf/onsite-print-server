#!/bin/bash
set +x
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: bash pull-images.sh (set image versions in .env.production)" >&2
  exit 1
fi

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ -z "${CR_PAT:-}" ]]; then
  echo "CR_PAT environment variable is not set (requires read:packages)" >&2
  exit 1
fi
if [[ ! -r .env.production ]]; then
  echo "Cannot read .env.production; set image tags before pulling" >&2
  exit 1
fi

compose=(docker compose --env-file .env.production -f compose.deploy.yaml)
"${compose[@]}" config --quiet
printf '%s' "$CR_PAT" |
  docker login ghcr.io -u "${GHCR_USERNAME:-groskopf}" --password-stdin
"${compose[@]}" pull

echo "Pulled production images successfully"
