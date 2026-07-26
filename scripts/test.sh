#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

export SNAPSHOT_ARTIFACTS="${SNAPSHOT_ARTIFACTS:-$repo_root/.build/snapshot-failures}"
mkdir -p "$SNAPSHOT_ARTIFACTS"

# shellcheck source=lib/typecheck-budget.sh
source "$repo_root/scripts/lib/typecheck-budget.sh"

# This is the entry point that covers the *test* target; `build.sh` only builds the app. The
# per-symbol budget diagnostics survive only in the raw stream, so budget mode tees a copy for the
# scan while still showing the xcsift summary - a full raw test log is far too large to read.
typecheck_budget_log=""
if [ -n "${TYPECHECK_BUDGET_MS:-}" ]; then
  typecheck_budget_log=$(mktemp -t alveary-typecheck-budget-test.XXXXXX)
fi

tmp_args=""
cleanup() {
  rm -f ${typecheck_budget_log:+"$typecheck_budget_log"} ${tmp_args:+"$tmp_args"}
}
trap cleanup EXIT

run_xcodebuild() {
  local status
  set +e
  if [ -n "$typecheck_budget_log" ] && command -v xcsift >/dev/null 2>&1; then
    "$@" 2>&1 | tee "$typecheck_budget_log" | xcsift -f toon -w
    status=${PIPESTATUS[0]}
  elif [ -n "$typecheck_budget_log" ]; then
    "$@" 2>&1 | tee "$typecheck_budget_log"
    status=${PIPESTATUS[0]}
  elif command -v xcsift >/dev/null 2>&1; then
    "$@" 2>&1 | xcsift -f toon -w
    status=${PIPESTATUS[0]}
  else
    "$@"
    status=$?
  fi
  set -e
  return "$status"
}

if [ "$#" -eq 0 ]; then
  run_xcodebuild xcodebuild \
    -project Alveary.xcodeproj \
    -scheme Alveary \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    test \
    "${typecheck_budget_flags[@]+"${typecheck_budget_flags[@]}"}"
else
  tmp_args=$(mktemp)

  for test_name in "$@"; do
    printf '%s\0' "-only-testing:$test_name" >> "$tmp_args"
  done

  run_xcodebuild xargs -0 xcodebuild \
    -project Alveary.xcodeproj \
    -scheme Alveary \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    test \
    "${typecheck_budget_flags[@]+"${typecheck_budget_flags[@]}"}" < "$tmp_args"
fi

echo "Tests passed."

if [ -n "$typecheck_budget_log" ]; then
  # Test sources fail at the (higher) test threshold; see typecheck-budget.sh for why the
  # compiler flag itself stays at the base budget.
  typecheck_budget_report_offenders "$typecheck_budget_log" "$repo_root" \
    "${TYPECHECK_TEST_BUDGET_MS:-${TYPECHECK_BUDGET_MS:-0}}"
fi
