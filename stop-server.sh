#!/bin/bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: bash stop-server.sh" >&2
  exit 1
fi

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ! -r .env.production ]]; then
  echo "Cannot read .env.production; restore the deployment configuration before stopping" >&2
  exit 1
fi

docker compose --env-file .env.production -f compose.deploy.yaml down
echo "Production server stopped; database volume preserved"
