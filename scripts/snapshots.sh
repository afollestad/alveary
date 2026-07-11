#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

usage() {
  cat <<'EOF'
Usage: ./scripts/snapshots.sh <verify|record> [test_identifier ...]

Defaults to the full `AlvearyTests/SnapshotTests` suite when no test identifiers are provided.

Examples:
  ./scripts/snapshots.sh verify
  ./scripts/snapshots.sh verify AlvearyTests/SnapshotTests/testSidebarViewPopulated
  ./scripts/snapshots.sh record
  ./scripts/snapshots.sh record AlvearyTests/SnapshotTests/testSidebarViewPopulated
EOF
}

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

default_snapshot_artifacts="$repo_root/.build/snapshot-failures"
if [ -z "${SNAPSHOT_ARTIFACTS:-}" ]; then
  export SNAPSHOT_ARTIFACTS="$default_snapshot_artifacts"
fi
if [ "$SNAPSHOT_ARTIFACTS" = "$default_snapshot_artifacts" ] || [ "$SNAPSHOT_ARTIFACTS" = ".build/snapshot-failures" ]; then
  rm -rf "$SNAPSHOT_ARTIFACTS"
fi
mkdir -p "$SNAPSHOT_ARTIFACTS"

run_and_format() {
  if command -v xcsift >/dev/null 2>&1; then
    "$@" 2>&1 | xcsift -f toon -w
  else
    "$@"
  fi
}

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 1
fi

mode=$1
shift

case "$mode" in
  verify|record)
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if [ "$#" -eq 0 ]; then
  set -- "AlvearyTests/SnapshotTests"
fi

tmp_args=$(mktemp)
patched_xctestrun=""
trap 'rm -f "$tmp_args" ${patched_xctestrun:+"$patched_xctestrun"}' EXIT

write_test_args() {
  : > "$tmp_args"
  for test_name in "$@"; do
    printf '%s\0' "-only-testing:$test_name" >> "$tmp_args"
  done
}

write_test_args "$@"

run_build_for_testing() {
  run_and_format xargs -0 xcodebuild \
    -project Alveary.xcodeproj \
    -scheme Alveary \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    build-for-testing < "$tmp_args"
}

prepare_patched_xctestrun() {
  local suffix=$1
  local records_snapshots=$2
  local forces_fixed_scale=$3
  local xctestrun_path
  xctestrun_path=$(find .build/xcode/Build/Products \
    -name '*.xctestrun' \
    ! -name '*.record.xctestrun' \
    ! -name '*.fixed-scale.xctestrun' \
    | head -n 1)
  if [ -z "$xctestrun_path" ]; then
    echo "error: Unable to find generated .xctestrun file after build-for-testing." >&2
    exit 1
  fi

  if [ -n "$patched_xctestrun" ]; then
    rm -f "$patched_xctestrun"
  fi
  local xctestrun_dir
  local xctestrun_name
  xctestrun_dir=$(dirname "$xctestrun_path")
  xctestrun_name=$(basename "$xctestrun_path" .xctestrun)
  patched_xctestrun="$xctestrun_dir/$xctestrun_name.$suffix.xctestrun"
  cp "$xctestrun_path" "$patched_xctestrun"

  python3 - "$patched_xctestrun" "$records_snapshots" "$forces_fixed_scale" <<'PY'
import plistlib
import sys

path = sys.argv[1]
records_snapshots = sys.argv[2] == 'true'
forces_fixed_scale = sys.argv[3] == 'true'
with open(path, 'rb') as file:
    data = plistlib.load(file)

for configuration in data.get('TestConfigurations', []):
    for target in configuration.get('TestTargets', []):
        values = {}
        if records_snapshots:
            values['RECORD_SNAPSHOTS'] = '1'
        if forces_fixed_scale:
            values['ALVEARY_FORCE_FIXED_SCALE_SNAPSHOTS'] = 'true'

        for key in ('EnvironmentVariables', 'TestingEnvironmentVariables'):
            target.setdefault(key, {}).update(values)

with open(path, 'wb') as file:
    plistlib.dump(data, file)
PY
}

run_patched_tests() {
  run_and_format xargs -0 xcodebuild \
    -xctestrun "$patched_xctestrun" \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    test-without-building < "$tmp_args"
}

run_verify() {
  if [ "${ALVEARY_FORCE_FIXED_SCALE_SNAPSHOTS:-}" = "true" ]; then
    run_build_for_testing
    prepare_patched_xctestrun fixed-scale false true
    run_patched_tests
    return
  fi

  run_and_format xargs -0 xcodebuild \
    -project Alveary.xcodeproj \
    -scheme Alveary \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    test < "$tmp_args"
}

if [ "$mode" = "verify" ]; then
  run_verify
  echo "Snapshot verification passed."
  exit 0
fi

run_build_for_testing
prepare_patched_xctestrun record true false

set +e
run_patched_tests
record_status=$?
set -e

if [ "$record_status" -ne 0 ]; then
  echo "Snapshot record command exited $record_status; verifying recorded references..."
fi

run_verify
echo "Snapshots recorded and verified."
