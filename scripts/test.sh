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
xcsift_summary=""
cleanup() {
  rm -f ${typecheck_budget_log:+"$typecheck_budget_log"} ${tmp_args:+"$tmp_args"} \
    ${xcsift_summary:+"$xcsift_summary"}
}
trap cleanup EXIT

# Any warning fails the run, including the runtime issues XCTest surfaces (AppKit view geometry and
# constraint conflicts, SwiftUI environment reads outside a view, Thread Performance Checker
# priority inversions). The gate reads xcsift's `warnings` count rather than using its
# `--Werror`/`--exit-on-failure`: those also fail on xcsift's own test bookkeeping, which has
# reported a passing Swift Testing case as "did not complete" in slow runs, while xcodebuild's
# exit status stays the authority on test failures. The no-xcsift fallback cannot enforce this, so
# CI installs xcsift through setup.sh.
run_xcodebuild() {
  local status
  set +e
  if [ -n "$typecheck_budget_log" ] && command -v xcsift >/dev/null 2>&1; then
    xcsift_summary=$(mktemp -t alveary-xcsift-test.XXXXXX)
    "$@" 2>&1 | tee "$typecheck_budget_log" | xcsift -f toon -w | tee "$xcsift_summary"
    status=${PIPESTATUS[0]}
  elif [ -n "$typecheck_budget_log" ]; then
    "$@" 2>&1 | tee "$typecheck_budget_log"
    status=${PIPESTATUS[0]}
  elif command -v xcsift >/dev/null 2>&1; then
    xcsift_summary=$(mktemp -t alveary-xcsift-test.XXXXXX)
    "$@" 2>&1 | xcsift -f toon -w | tee "$xcsift_summary"
    status=${PIPESTATUS[0]}
  else
    "$@"
    status=$?
  fi
  set -e
  if [ "$status" -eq 0 ] && [ -n "$xcsift_summary" ] && grep -Eq '^  warnings: [1-9]' "$xcsift_summary"; then
    echo "Tests emitted warnings; fix them (see warnings[] above)." >&2
    status=1
  fi
  return "$status"
}

# AppKit drives frame animations and legacy wheel scrolling from display-link ticks, which stop
# while the display sleeps, so a run that outlasts the display-sleep timer fails the animation and
# scroll-routing tests. `caffeinate` holds the display (and the machine) awake for the run.
keep_awake=()
if command -v caffeinate >/dev/null 2>&1; then
  keep_awake=(caffeinate -d -i)
fi

if [ "$#" -eq 0 ]; then
  run_xcodebuild "${keep_awake[@]+"${keep_awake[@]}"}" xcodebuild \
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

  run_xcodebuild xargs -0 "${keep_awake[@]+"${keep_awake[@]}"}" xcodebuild \
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
