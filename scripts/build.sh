#!/bin/bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

run_and_format() {
  if command -v xcbeautify >/dev/null 2>&1; then
    # Tee the raw xcodebuild stream to a temp log and track whether xcbeautify
    # produced any output. On failure we only fall back to the raw log when
    # xcbeautify swallowed everything (e.g. plug-in load failures it doesn't
    # recognize); otherwise the formatted output already shows the error.
    raw_log=$(mktemp -t alveary-xcodebuild.XXXXXX)
    filtered_log=$(mktemp -t alveary-xcbeautify.XXXXXX)
    trap 'rm -f "$raw_log" "$filtered_log"' EXIT
    # Hide xcbeautify's startup/version banner so the script output stays focused on build results.
    if ! "$@" 2>&1 | tee "$raw_log" | xcbeautify --disable-logging | tee "$filtered_log"; then
      status=${PIPESTATUS[0]}
      if [ ! -s "$filtered_log" ]; then
        echo "" >&2
        echo "xcodebuild exited $status and xcbeautify produced no output — raw log:" >&2
        cat "$raw_log" >&2
      fi
      exit "$status"
    fi
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
