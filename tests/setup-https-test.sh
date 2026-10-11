#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -f -- "$temp/docker" "$temp/calls" "$temp/output" "$temp/setup-https.sh" "$temp/start-server.sh" "$temp/check-certificate.sh" "$temp/.env.production"; rmdir -- "$temp"' EXIT
cp "$root/setup-https.sh" "$root/check-certificate.sh" "$temp/"
cat > "$temp/start-server.sh" <<'MOCK'
#!/bin/bash
printf 'start-server %s\n' "$*" >> "$CALLS"
MOCK
cat > "$temp/docker" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$CALLS"
if [[ " $* " == *" run "*"/etc/letsencrypt/live/"* ]]; then
  exit "${CERT_STATUS:-3}"
elif [[ " $* " == *" run "* ]]; then
  [[ "$ACME_EMAIL" == admin@example.com ]]
  [[ " $* " == *" --no-deps "* ]]
  [[ " $* " == *" -p 80:80 "* ]]
  if [[ "${FAIL_ISSUANCE:-}" == 1 ]]; then exit 42; fi
fi
MOCK
chmod +x "$temp/docker"
export PATH="$temp:$PATH" CALLS="$temp/calls"
unset FAIL_ISSUANCE

if bash "$temp/setup-https.sh" > "$temp/output" 2>&1; then
  echo "Missing email was accepted" >&2
  exit 1
fi
if bash "$temp/setup-https.sh" admin@example.com > "$temp/output" 2>&1; then
  echo "Missing production configuration was accepted" >&2
  exit 1
fi
printf 'TLS_DOMAIN=event.onsite-print.dk\n' > "$temp/.env.production"
: > "$CALLS"
export FAIL_ISSUANCE=1
if bash "$temp/setup-https.sh" admin@example.com > "$temp/output" 2>&1; then
  echo "Failed issuance was accepted" >&2
  exit 1
fi
! grep -q '^start-server' "$CALLS"
unset FAIL_ISSUANCE
: > "$CALLS"
(cd / && bash "$temp/setup-https.sh" admin@example.com) > "$temp/output" 2>&1
[[ "$(sed -n '1p' "$CALLS")" == 'compose --env-file .env.production -f compose.deploy.yaml config --quiet' ]]
[[ "$(sed -n '2p' "$CALLS")" == *' run --rm --no-deps --entrypoint /bin/sh certbot -c '* ]]
[[ "$(sed -n '3p' "$CALLS")" == 'compose --env-file .env.production -f compose.deploy.yaml stop certbot nginx' ]]
! grep -q ' pull' "$CALLS"
[[ "$(tail -n 1 "$CALLS")" == 'start-server ' ]]
grep -q -- '--standalone' "$CALLS"

export CERT_STATUS=0
: > "$CALLS"
bash "$temp/setup-https.sh" admin@example.com > "$temp/output" 2>&1
grep -q 'already exists; skipping issuance' "$temp/output"
! grep -q -- '--standalone\| stop ' "$CALLS"
[[ "$(tail -n 1 "$CALLS")" == 'start-server ' ]]

export CERT_STATUS=42
: > "$CALLS"
if bash "$temp/setup-https.sh" admin@example.com > "$temp/output" 2>&1; then
  echo "Failed certificate check was accepted" >&2
  exit 1
fi
! grep -q -- '--standalone\| stop \|^start-server' "$CALLS"
unset CERT_STATUS
echo "Certificate setup orchestration tests passed"
