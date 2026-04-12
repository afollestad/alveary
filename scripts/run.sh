#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
app_path="$repo_root/.build/xcode/Build/Products/Debug/Skep.app"

if [ ! -d "$app_path" ]; then
  echo "Skep.app not found, building first..."
  "$repo_root/scripts/build.sh"
fi

echo "Running the app without building..."
open "$app_path"
