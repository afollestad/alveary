#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)

sh "$repo_root/scripts/setup/install-tools.sh"

echo "Generating Xcode project..."
xcodegen generate

echo "Installing Git hooks..."
"$repo_root/scripts/setup/install-git-hooks.sh"

echo "Setup complete. Next steps:"
echo "  1. If you want to view the project in XCode: `open Skep.xcodeproj`"
echo "  2. Re-run 'xcodegen generate' any time you change project structure or dependencies, then re-open Skep.xcodeproj."
echo "  3. Build with './scripts/build.sh', test with './scripts/test.sh', verify snapshots with './scripts/snapshots.sh verify', or launch with './scripts/run.sh'."
