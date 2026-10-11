#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: bash setup-https.sh <Let's Encrypt contact email>" >&2
  exit 1
fi
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ! -r .env.production ]]; then
  echo "Cannot read .env.production" >&2
  exit 1
fi
export ACME_EMAIL="$1"
compose=(docker compose --env-file .env.production -f compose.deploy.yaml)
"${compose[@]}" config --quiet
status=0
bash check-certificate.sh > /dev/null 2>&1 || status=$?
if [[ "$status" -eq 0 ]]; then
  echo "HTTPS certificate already exists; skipping issuance. See README to replace it."
  exec bash start-server.sh
elif [[ "$status" -ne 3 ]]; then
  echo "Could not check for an existing HTTPS certificate (exit $status)" >&2
  exit "$status"
fi
"${compose[@]}" stop certbot nginx
echo "nginx stopped temporarily for certificate issuance on port 80"
"${compose[@]}" run --rm --no-deps -p 80:80 -e ACME_EMAIL --entrypoint /bin/sh certbot -c \
  'exec certbot certonly --non-interactive --agree-tos --email "$ACME_EMAIL" --cert-name "$TLS_DOMAIN" -d "$TLS_DOMAIN" --standalone --preferred-challenges http'
bash start-server.sh
