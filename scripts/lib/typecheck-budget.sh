#!/bin/bash
# Shared type-check budget flags, sourced by every script that drives xcodebuild.
#
# Swift solves an expression as a whole, and when the solver runs out of time it hard-errors
# instead of warning. That limit is wall-clock, so an over-budget SwiftUI body compiles fine on a
# fast machine and fails only on slower CI hardware. Setting TYPECHECK_BUDGET_MS asks the frontend
# to warn past that many milliseconds; `build.sh` additionally fails on any such warning.
#
# Every entry point applies the same flags so one CI compile serves the build, test, and snapshot
# steps. If only some of them set OTHER_SWIFT_FLAGS, the others see different build settings and
# recompile the whole app target from scratch.
#
# Populates `typecheck_budget_flags`. Expand it as "${typecheck_budget_flags[@]+"${typecheck_budget_flags[@]}"}"
# so an empty array stays safe under `set -u`.

typecheck_budget_flags=()
if [ -n "${TYPECHECK_BUDGET_MS:-}" ]; then
  typecheck_budget_flags+=(
    "OTHER_SWIFT_FLAGS=\$(inherited) -Xfrontend -warn-long-function-bodies=${TYPECHECK_BUDGET_MS} -Xfrontend -warn-long-expression-type-checking=${TYPECHECK_BUDGET_MS}"
  )
fi

# Fails when a raw xcodebuild log contains an over-budget diagnostic for this repo's own sources.
#
# `build.sh` scans the app target and `test.sh` scans the test target, because the two compile
# different sources and a budget that only covered one would let the other drift. Generated macro
# expansion buffers (`@__swiftmacro_…`, mostly `#Predicate`) restate a diagnostic already reported
# at their call site and cannot be edited, and `.build/` dependency sources are not ours to change,
# so both are excluded. `awk` matches the prefix literally, so a repo path containing regex or
# `sed` delimiter characters stays safe.
#
# An optional third argument raises the failure threshold above the warning flag. The solver's
# wall-clock timer bills first-touch framework deserialization to whichever expression in a
# frontend batch needs it first, so a trivial test statement can report several seconds on CI
# while solving in under 100ms locally — noise no restructuring can remove, observed only in
# test sources.
# `test.sh` therefore fails at `TYPECHECK_TEST_BUDGET_MS` (defaulting to the base budget) while
# the compiler flag stays at the base value everywhere, keeping build settings identical so every
# step shares one set of products. Sub-threshold reports still surface as plain warnings.
typecheck_budget_report_offenders() {
  local log_path=$1
  local root=$2
  local fail_threshold_ms=${3:-${TYPECHECK_BUDGET_MS:-0}}
  local offenders
  offenders=$(
    grep -E "took [0-9]+ms to type-check" "$log_path" \
      | awk -v root="$root/" -v build="$root/.build/" -v limit="$fail_threshold_ms" \
        'index($0, root) == 1 && index($0, build) != 1 {
           line = substr($0, length(root) + 1)
           if (match(line, /took [0-9]+ms to type-check/)) {
             ms = substr(line, RSTART + 5)
             sub(/ms.*/, "", ms)
             if (ms + 0 >= limit + 0) { print line }
           }
         }' \
      | sort -u || true
  )

  if [ -z "$offenders" ]; then
    return 0
  fi

  echo "" >&2
  echo "Type-check budget exceeded (failure threshold ${fail_threshold_ms}ms, warnings from ${TYPECHECK_BUDGET_MS:-}ms):" >&2
  echo "$offenders" >&2
  echo "" >&2
  echo "Split each into parts that type-check on their own; see the type-check budget bullets in AGENTS.md." >&2
  return 1
}
