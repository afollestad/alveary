#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
app_path="$repo_root/.build/xcode/Build/Products/Debug/Alveary.app"
app_name="Alveary"

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

if [ ! -d "$app_path" ]; then
  echo "Alveary.app not found, building first..."
  "$repo_root/scripts/build.sh"
fi

open "$app_path"
