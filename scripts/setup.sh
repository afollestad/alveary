#!/bin/sh
set -eu

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

repo_root=$(git rev-parse --show-toplevel)
required_needle_version=0.25.1

if ! command -v brew >/dev/null 2>&1; then
  echo "error: Homebrew is required. Install it from https://brew.sh/ and rerun this script." >&2
  exit 1
fi

install_brew_formula() {
  formula=$1
  if brew list --formula "$formula" >/dev/null 2>&1; then
    echo "$formula already installed"
  else
    brew install "$formula"
  fi
}

require_command() {
  command_name=$1
  install_hint=$2
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: $command_name is required. $install_hint" >&2
    exit 1
  fi
}

require_needle_version() {
  require_command needle "Install it with 'brew install needle' or rerun ./scripts/setup.sh."
  actual_version=$(needle version 2>/dev/null || true)
  if [ "$actual_version" != "$required_needle_version" ]; then
    echo "error: needle $required_needle_version is required to match the pinned NeedleFoundation package. Found: ${actual_version:-unknown}." >&2
    echo "Install the required version or update project.yml and the generated DI output together." >&2
    exit 1
  fi
}

install_brew_formula xcodegen
install_brew_formula xcsift
install_brew_formula swiftlint
install_brew_formula needle
require_needle_version

echo "Generating Xcode project..."
xcodegen generate

if [ "${CI:-false}" = "true" ]; then
  echo "Skipping Git hook installation in CI."
else
  echo "Installing Git hooks..."
  if ! "$repo_root/scripts/install-git-hooks.sh"; then
    echo "warning: Git hook installation failed; continuing setup." >&2
  fi
fi

green=$(printf '\033[32m')
reset=$(printf '\033[0m')

echo "Setup complete. Next steps:"
echo "  1. If you want to view the project in XCode: ${green}open Alveary.xcodeproj${reset}"
echo "  2. Re-run ${green}xcodegen generate${reset} any time you change project structure or dependencies, then re-open Alveary.xcodeproj."
echo "  3. Build with ${green}./scripts/build.sh${reset}, test with ${green}./scripts/test.sh${reset}, lint with ${green}./scripts/lint.sh${reset}, verify snapshots with ${green}./scripts/snapshots.sh verify${reset}, or launch with ${green}./scripts/run.sh${reset}."
