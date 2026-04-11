#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)

chmod +x "$repo_root/.githooks/pre-commit"
git -C "$repo_root" config core.hooksPath .githooks

echo "Configured repo-local Git hooks at .githooks"
echo "Pre-commit hook: $repo_root/.githooks/pre-commit"
