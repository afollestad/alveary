#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

use_xcsift=true
if [ "${1:-}" = "--no-xcsift" ]; then
  use_xcsift=false
  shift
fi

# shellcheck source=lib/typecheck-budget.sh
source "$repo_root/scripts/lib/typecheck-budget.sh"

# This is the only entry point that *fails* on the budget; the others just match its build
# settings so the compiled products stay shared.
typecheck_budget_ms="${TYPECHECK_BUDGET_MS:-}"
typecheck_budget_log=""
if [ -n "$typecheck_budget_ms" ]; then
  typecheck_budget_log=$(mktemp -t alveary-typecheck-budget.XXXXXX)
  trap 'rm -f "$typecheck_budget_log"' EXIT
  # The warnings exist only in the raw compiler stream; xcsift reduces it to counts and a
  # summary, so the scan below would find nothing to fail on. Forcing this off also keeps the
  # trap above from colliding with the one `run_and_format` installs for its own logs.
  use_xcsift=false
fi

run_and_format() {
  if [ "$use_xcsift" = true ] && command -v xcsift >/dev/null 2>&1; then
    # Tee the raw xcodebuild stream to a temp log and track whether xcsift
    # produced any output. On failure we only fall back to the raw log when
    # xcsift swallowed everything (e.g. plug-in load failures it doesn't
    # recognize); otherwise the formatted output already shows the error.
    raw_log=$(mktemp -t alveary-xcodebuild.XXXXXX)
    filtered_log=$(mktemp -t alveary-xcsift.XXXXXX)
    trap 'rm -f "$raw_log" "$filtered_log"' EXIT
    set +e
    "$@" 2>&1 | tee "$raw_log" | xcsift -f toon -w | tee "$filtered_log"
    statuses=("${PIPESTATUS[@]}")
    set -e

    status=0
    for pipeline_status in "${statuses[@]}"; do
      if [ "$pipeline_status" -ne 0 ]; then
        status=$pipeline_status
      fi
    done

    if [ "$status" -ne 0 ]; then
      xcodebuild_status=${statuses[0]:-0}
      raw_tee_status=${statuses[1]:-0}
      xcsift_status=${statuses[2]:-0}
      final_tee_status=${statuses[3]:-0}

      if [ "$xcodebuild_status" -ne 0 ] && [ ! -s "$filtered_log" ]; then
        echo "" >&2
        echo "xcodebuild exited $xcodebuild_status and xcsift produced no output - raw log:" >&2
        cat "$raw_log" >&2
      elif [ "$xcodebuild_status" -eq 0 ]; then
        echo "" >&2
        echo "build output formatting failed (raw tee: $raw_tee_status, xcsift: $xcsift_status, final tee: $final_tee_status)" >&2
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

build_command=(
  xcodebuild
  -project Alveary.xcodeproj
  -scheme Alveary
  -configuration Debug
  -destination 'platform=macOS'
  -derivedDataPath .build/xcode
  build
  "${typecheck_budget_flags[@]+"${typecheck_budget_flags[@]}"}"
  "$@"
)

if [ -z "$typecheck_budget_log" ]; then
  run_and_format "${build_command[@]}"
  exit 0
fi

set +e
run_and_format "${build_command[@]}" 2>&1 | tee "$typecheck_budget_log"
build_status=${PIPESTATUS[0]}
set -e

if [ "$build_status" -ne 0 ]; then
  exit "$build_status"
fi

# The frontend emits these only past the limit, so any match is over budget. Keep only sources in
# this repository: compiler-generated macro expansion buffers (`@__swiftmacro_…`, mostly
# `#Predicate`) just restate the diagnostic already reported at their call site and cannot be
# edited, and dependency sources under `.build/` are not ours to change. `awk` matches the prefix
# literally, so a repo path containing regex or `sed` delimiter characters stays safe.
offenders=$(
  grep -E "took [0-9]+ms to type-check" "$typecheck_budget_log" \
    | awk -v root="$repo_root/" -v build="$repo_root/.build/" \
      'index($0, root) == 1 && index($0, build) != 1 { print substr($0, length(root) + 1) }' \
    | sort -u || true
)

if [ -n "$offenders" ]; then
  echo "" >&2
  echo "Type-check budget exceeded (TYPECHECK_BUDGET_MS=$typecheck_budget_ms):" >&2
  echo "$offenders" >&2
  echo "" >&2
  echo "Split each into parts that type-check on their own; see the type-check budget bullets in AGENTS.md." >&2
  exit 1
fi
