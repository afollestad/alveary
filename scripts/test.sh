#!/bin/bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if [ "$#" -eq 0 ]; then
  xcodebuild \
    -project Skep.xcodeproj \
    -scheme Skep \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    test \
    2>&1 | xcbeautify
  echo "Tests passed."
  exit 0
fi

tmp_args=$(mktemp)
trap 'rm -f "$tmp_args"' EXIT

for test_arg in "$@"; do
  case "$test_arg" in
    -*)
      printf '%s\0' "$test_arg" >> "$tmp_args"
      ;;
    *)
      printf '%s\0' "-only-testing:$test_arg" >> "$tmp_args"
      ;;
  esac
done

xargs -0 xcodebuild \
  -project Skep.xcodeproj \
  -scheme Skep \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode \
  test < "$tmp_args" \
  2>&1 | xcbeautify

echo "Tests passed."
