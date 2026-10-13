#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -f -- "$temp/docker" "$temp/calls" "$temp/output" "$temp/docker-push.sh" "$temp/.env"; rmdir -- "$temp"' EXIT

cat > "$temp/docker" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s|%s|%s\n' "$*" "${IMAGE_TAG:-}" "$PWD" >> "$CALLS"
if [[ "$1" == login ]]; then
  [[ "$(cat)" == test-secret ]]
fi
if [[ "${FAIL_STEP:-}" == "$1 ${2:-}" ]]; then
  echo "Simulated Docker failure" >&2
  exit 42
fi
MOCK
chmod +x "$temp/docker"
export PATH="$temp:$PATH"
export CALLS="$temp/calls"
export GHCR_USERNAME=test-user
unset FAIL_STEP

expect_failure() {
  : > "$CALLS"
  if bash "$temp/docker-push.sh" "$@" > "$temp/output" 2>&1; then
    echo "Expected publishing to fail: $* (setting: ${setting:-unset}, repo: $repo)" >&2
    exit 1
  fi
  if grep -q 'Published\|test-secret' "$temp/output"; then
    echo "Failure output leaked a token or reported success" >&2
    exit 1
  fi
}

for repo in web-server database backend attendee checkin; do
  case "$repo" in
    web-server) app="nginx certbot" ;;
    database) app=postgres ;;
    *) app="$repo" ;;
  esac
  cp "$root/../onsite-print-$repo/docker-push.sh" "$temp/docker-push.sh"
  auto_increment=false
  if grep -q 'next_patch' "$temp/docker-push.sh"; then
    auto_increment=true
  fi
  export CR_PAT=test-secret
  printf '%s\n' IMAGE_TAG=1.0.0 > "$temp/.env"
  expect_failure 1.0.0
  [[ ! -s "$CALLS" ]]
  rm -- "$temp/.env"
  expect_failure
  [[ ! -s "$CALLS" ]]
  if [[ "$auto_increment" == true ]]; then
    invalid_settings=('' 'IMAGE_TAG=' 'IMAGE_TAG=latest' 'IMAGE_TAG=1.0' 'IMAGE_TAG=01.0.0' 'IMAGE_TAG=1.0.0-rc1' 'IMAGE_TAG=invalid/tag' 'IMAGE_TAG=1.0.0 extra' $'IMAGE_TAG=1.0.0\nEXTRA=value')
  else
    invalid_settings=('' 'IMAGE_TAG=' 'IMAGE_TAG=invalid/tag' 'IMAGE_TAG=1.0.0 extra' $'IMAGE_TAG=1.0.0\nEXTRA=value')
  fi
  for setting in "${invalid_settings[@]}"; do
    printf '%s\n' "$setting" > "$temp/.env"
    expect_failure
    [[ ! -s "$CALLS" ]]
  done
  unset setting
  printf '%s\n' IMAGE_TAG=1.0.0 > "$temp/.env"
  unset CR_PAT
  expect_failure
  [[ ! -s "$CALLS" ]]
  export CR_PAT=test-secret
  for step in 'login ghcr.io' 'compose build' 'compose push'; do
    export FAIL_STEP="$step"
    expect_failure
    [[ "$(tail -n 1 "$CALLS")" == "$step"* ]]
    [[ "$(cat "$temp/.env")" == IMAGE_TAG=1.0.0 ]]
  done
  unset FAIL_STEP
  : > "$CALLS"
  export IMAGE_TAG=ignored-shell-tag
  (cd / && bash "$temp/docker-push.sh") > "$temp/output" 2>&1
  expected="$(printf '%s\n' \
    "login ghcr.io -u test-user --password-stdin|1.0.0|$temp" \
    "compose build --pull $app|1.0.0|$temp" \
    "compose push $app|1.0.0|$temp")"
  [[ "$(cat "$CALLS")" == "$expected" ]]
  grep -q "Published ghcr.io/groskopf/onsite-print-$repo:1.0.0" "$temp/output"
  ! grep -q test-secret "$temp/output"
  if [[ "$auto_increment" == true ]]; then
    [[ "$(cat "$temp/.env")" == IMAGE_TAG=1.0.1 ]]
    for versions in '1.2.9 1.2.10' '1.2.99 1.2.100' '1.2.99999999999999999999 1.2.100000000000000000000'; do
      read -r current next <<< "$versions"
      printf 'IMAGE_TAG=%s\n' "$current" > "$temp/.env"
      bash "$temp/docker-push.sh" > "$temp/output" 2>&1
      [[ "$(cat "$temp/.env")" == "IMAGE_TAG=$next" ]]
    done
  else
    [[ "$(cat "$temp/.env")" == IMAGE_TAG=1.0.0 ]]
    for tag in latest 1.0 01.0.0 1.0.0-rc1 1.2.9 1.2.99 1.2.99999999999999999999; do
      : > "$CALLS"
      printf 'IMAGE_TAG=%s\n' "$tag" > "$temp/.env"
      bash "$temp/docker-push.sh" > "$temp/output" 2>&1
      [[ "$(cat "$temp/.env")" == "IMAGE_TAG=$tag" ]]
      expected="$(printf '%s\n' \
        "login ghcr.io -u test-user --password-stdin|$tag|$temp" \
        "compose build --pull $app|$tag|$temp" \
        "compose push $app|$tag|$temp")"
      [[ "$(cat "$CALLS")" == "$expected" ]]
      grep -q "Published ghcr.io/groskopf/onsite-print-$repo:$tag" "$temp/output"
      ! grep -q test-secret "$temp/output"
    done
  fi
done
echo "Publishing and patch increment tests passed for all five images"
