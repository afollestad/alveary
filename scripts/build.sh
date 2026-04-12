#!/bin/bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

echo "Building the app from source..."

xcodebuild \
  -project Skep.xcodeproj \
  -scheme Skep \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode \
  build \
  "$@" \
  2>&1 | xcbeautify

echo "Build succeeded."
