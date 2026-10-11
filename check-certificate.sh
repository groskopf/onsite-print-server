#!/bin/bash
set -euo pipefail

# Exit codes: 0 = certificate found, 3 = certificate missing, other = check failed.
if [[ $# -ne 0 ]]; then
  echo "Usage: bash check-certificate.sh" >&2
  exit 1
fi

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ! -r .env.production ]]; then
  echo "Cannot read .env.production" >&2
  exit 1
fi

compose=(docker compose --env-file .env.production -f compose.deploy.yaml)
status=0
"${compose[@]}" run --rm --no-deps --entrypoint /bin/sh certbot -c \
  'live="/etc/letsencrypt/live/$TLS_DOMAIN"; test -s "$live/fullchain.pem" && test -s "$live/privkey.pem" || exit 3' \
  || status=$?

case "$status" in
  0) echo "HTTPS certificate is set up" ;;
  3) echo "No HTTPS certificate found; run: bash setup-https.sh <email>" >&2 ;;
  *) echo "Could not check the HTTPS certificate (exit $status)" >&2 ;;
esac
exit "$status"
