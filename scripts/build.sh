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
    set +e
    "$@" 2>&1 | tee "$raw_log" | xcbeautify --disable-logging | tee "$filtered_log"
    status=$?
    statuses=("${PIPESTATUS[@]}")
    set -e

    if [ "$status" -ne 0 ]; then
      xcodebuild_status=${statuses[0]:-0}
      raw_tee_status=${statuses[1]:-0}
      xcbeautify_status=${statuses[2]:-0}
      final_tee_status=${statuses[3]:-0}

      if [ "$xcodebuild_status" -ne 0 ] && [ ! -s "$filtered_log" ]; then
        echo "" >&2
        echo "xcodebuild exited $xcodebuild_status and xcbeautify produced no output — raw log:" >&2
        cat "$raw_log" >&2
      elif [ "$xcodebuild_status" -eq 0 ]; then
        echo "" >&2
        echo "build output formatting failed (raw tee: $raw_tee_status, xcbeautify: $xcbeautify_status, final tee: $final_tee_status)" >&2
        if [ ! -s "$filtered_log" ]; then
          echo "raw xcodebuild log:" >&2
          cat "$raw_log" >&2
        fi
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
