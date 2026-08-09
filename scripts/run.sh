#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
app_path="$repo_root/.build/xcode/Build/Products/Debug/Alveary.app"
app_name="Alveary"

build_first=0
demo_mode=0
for arg in "$@"; do
  case "$arg" in
    -b|--build)
      build_first=1
      ;;
    -d|--demo)
      demo_mode=1
      ;;
    *)
      echo "error: unknown argument: $arg" >&2
      echo "usage: $0 [-b|--build] [-d|--demo]" >&2
      exit 1
      ;;
  esac
done

if [ "$build_first" -eq 1 ]; then
  "$repo_root/scripts/build.sh"
elif [ ! -d "$app_path" ]; then
  echo "Alveary.app not found, building first..."
  "$repo_root/scripts/build.sh"
fi

if pgrep -x "$app_name" >/dev/null 2>&1; then
  pkill -x "$app_name"

  attempt=0
  while pgrep -x "$app_name" >/dev/null 2>&1 && [ "$attempt" -lt 50 ]; do
    sleep 0.1
    attempt=$((attempt + 1))
  done

  if pgrep -x "$app_name" >/dev/null 2>&1; then
    pkill -9 -x "$app_name"
  fi
fi

if [ "$demo_mode" -eq 1 ]; then
  # `open --env` is a LaunchServices launch, matching the Developer menu's relaunch, so the two
  # routes produce the same environment.
  open --env ALVEARY_DEMO_MODE=1 "$app_path"
else
  open "$app_path"
fi
