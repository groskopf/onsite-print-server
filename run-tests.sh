#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -gt 2 || ( $# -gt 0 && "$1" != --smoke ) ]]; then
  echo "Usage: bash run-tests.sh [--smoke [base-url]]" >&2
  exit 1
fi

echo "Running setup-https-test"
bash "$root/tests/setup-https-test.sh"

if [[ $# -gt 0 ]]; then
  echo "Running smoke-test"
  bash "$root/tests/smoke-test.sh" "${2:-http://localhost:8080}"
fi

echo "All selected tests passed"
