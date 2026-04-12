#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
app_path="$repo_root/.build/xcode/Build/Products/Debug/Alveary.app"

if [ ! -d "$app_path" ]; then
  echo "Alveary.app not found, building first..."
  "$repo_root/scripts/build.sh"
fi

open "$app_path"
