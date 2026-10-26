#!/bin/bash
set +x
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: bash publish-images.sh (set image versions in each sibling's .env)" >&2
  exit 1
fi

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for repo in web-server database backend attendee checkin admin event; do
  script="$root/../onsite-print-$repo/docker-push.sh"
  if [[ ! -r "$script" ]]; then
    echo "Missing publishing script: $script" >&2
    exit 1
  fi
done

for repo in web-server database backend attendee checkin admin event; do
  bash "$root/../onsite-print-$repo/docker-push.sh"
done
