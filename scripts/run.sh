#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
app_path="$repo_root/.build/xcode/Build/Products/Debug/Alveary.app"
app_name="Alveary"

build_first=0
for arg in "$@"; do
  case "$arg" in
    -b|--build)
      build_first=1
      ;;
    *)
      echo "error: unknown argument: $arg" >&2
      echo "usage: $0 [-b|--build]" >&2
      exit 1
      ;;
  esac
done

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

if [ "$build_first" -eq 1 ]; then
  "$repo_root/scripts/build.sh"
elif [ ! -d "$app_path" ]; then
  echo "Alveary.app not found, building first..."
  "$repo_root/scripts/build.sh"
fi

open "$app_path"
