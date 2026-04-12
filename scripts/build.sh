#!/bin/bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# Hide xcbeautify's startup/version banner so the script output stays focused on build results.
xcodebuild \
  -project Skep.xcodeproj \
  -scheme Skep \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode \
  build \
  "$@" \
  2>&1 | xcbeautify --disable-logging

echo "Build succeeded."
