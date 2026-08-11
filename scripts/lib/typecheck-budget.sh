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
# frontend batch needs it first, so a trivial statement can report several seconds on CI while
# solving in under 100ms locally — noise no restructuring can remove.
# `test.sh` therefore fails at `TYPECHECK_TEST_BUDGET_MS` (defaulting to the base budget) while
# the compiler flag stays at the base value everywhere, keeping build settings identical so every
# step shares one set of products. Sub-threshold reports still surface as plain warnings.
#
# The prefixes below are exempt from the failure scan entirely, because each is where one of those
# deserializations lands rather than a body anyone can shorten. Their readings stay visible as
# warnings. Add one only with a measurement showing the same signature: multi-second on CI, trivial
# locally, and invariant to how the statement is written — the last part is what separates this
# from genuine cost, and the way to prove it is to put a throwaway function doing strictly *less*
# ahead of the reported one and confirm the whole bill moves onto it.
#
# One repo-relative path prefix per line; the scan joins them with commas for `awk`, so a prefix
# may not contain one. Matching is literal, through `index`.
#
#   AlvearyTests/App/AppDelegateTests — its statements are already trivial (explicitly typed
#   locals, single-candidate calls) and still drift upward across toolchains on untouched lines:
#   3063ms, then 5236ms, then 7116ms for the same `applicationDidFinishLaunching` call. Raising
#   the ceiling instead would take the whole test target past the point where a genuine
#   multi-second expression — the app-side `#Predicate` that measured 5965ms — is still caught.
#
#   Alveary/Views/Chat/Blocks/AppKit/Widgets/AppKitReviewProposalCommentChrome.swift — AppKit's
#   `NSMenu`/`NSMenuItem` metadata, billed to whichever function in the batch builds a menu first.
#   Measured 3264ms on CI for `makeMenu()`; locally on the same toolchain a four-line function
#   whose whole body is one all-literal `NSMenuItem` takes 1277ms and drops `makeMenu()` off the
#   report entirely. This file only pays it because it now sorts first among the menu-building
#   AppKit sources — the bill previously landed on `AppKitReviewProposalWidgetView` and passed
#   under the threshold there — so the reading is a property of file order, not of this code.
typecheck_budget_exempt_prefixes="AlvearyTests/App/AppDelegateTests
Alveary/Views/Chat/Blocks/AppKit/Widgets/AppKitReviewProposalCommentChrome.swift"

typecheck_budget_report_offenders() {
  local log_path=$1
  local root=$2
  local fail_threshold_ms=${3:-${TYPECHECK_BUDGET_MS:-0}}
  local offenders
  offenders=$(
    grep -E "took [0-9]+ms to type-check" "$log_path" \
      | awk -v root="$root/" -v build="$root/.build/" -v limit="$fail_threshold_ms" \
        -v exempt="$(printf '%s' "$typecheck_budget_exempt_prefixes" | tr '\n' ',')" \
        'BEGIN { exempt_count = split(exempt, exempt_prefixes, ",") }
         index($0, root) == 1 && index($0, build) != 1 {
           line = substr($0, length(root) + 1)
           for (i = 1; i <= exempt_count; i++) {
             if (exempt_prefixes[i] != "" && index(line, exempt_prefixes[i]) == 1) { next }
           }
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
