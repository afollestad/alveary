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
