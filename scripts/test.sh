#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

export SNAPSHOT_ARTIFACTS="${SNAPSHOT_ARTIFACTS:-$repo_root/.build/snapshot-failures}"
mkdir -p "$SNAPSHOT_ARTIFACTS"

run_and_format() {
  if command -v xcsift >/dev/null 2>&1; then
    "$@" 2>&1 | xcsift -f toon -w
  else
    "$@"
  fi
}

if [ "$#" -eq 0 ]; then
  run_and_format xcodebuild \
    -project Alveary.xcodeproj \
    -scheme Alveary \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    test
  echo "Tests passed."
  exit 0
fi

tmp_args=$(mktemp)
trap 'rm -f "$tmp_args"' EXIT

for test_name in "$@"; do
  printf '%s\0' "-only-testing:$test_name" >> "$tmp_args"
done

run_and_format xargs -0 xcodebuild \
  -project Alveary.xcodeproj \
  -scheme Alveary \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode \
  test < "$tmp_args"

echo "Tests passed."
