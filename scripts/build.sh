#!/bin/bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

run_and_format() {
  if command -v xcbeautify >/dev/null 2>&1; then
    # Hide xcbeautify's startup/version banner so the script output stays focused on build results.
    "$@" 2>&1 | xcbeautify --disable-logging
  else
    "$@"
  fi
}

run_and_format xcodebuild \
  -project Alveary.xcodeproj \
  -scheme Alveary \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode \
  build \
  "$@"
