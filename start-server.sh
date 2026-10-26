#!/bin/bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: bash start-server.sh" >&2
  exit 1
fi

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ! -r .env.production ]]; then
  echo "Cannot read .env.production; set image tags before starting" >&2
  exit 1
fi

docker compose --env-file .env.production -f compose.deploy.yaml up -d --pull never --wait --wait-timeout 120
echo "Production server started successfully"
