#!/bin/sh
set -eu

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "error: swiftlint is required. Install it with Homebrew or run ./scripts/setup.sh." >&2
  exit 1
fi

swiftlint
