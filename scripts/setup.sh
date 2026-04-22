#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)

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

install_brew_formula xcodegen
install_brew_formula xcbeautify
install_brew_formula swiftlint
install_brew_formula mint

if command -v knit-cli >/dev/null 2>&1; then
  echo "knit-cli already installed"
elif [ -x "$HOME/.mint/bin/knit-cli" ]; then
  echo "knit-cli already installed at $HOME/.mint/bin/knit-cli"
else
  mint install cashapp/knit knit-cli
fi

echo "Generating Xcode project..."
xcodegen generate

echo "Installing Git hooks..."
"$repo_root/scripts/install-git-hooks.sh"

green=$(printf '\033[32m')
reset=$(printf '\033[0m')

echo "Setup complete. Next steps:"
echo "  1. If you want to view the project in XCode: ${green}open Alveary.xcodeproj${reset}"
echo "  2. Re-run ${green}xcodegen generate${reset} any time you change project structure or dependencies, then re-open Alveary.xcodeproj."
echo "  3. Build with ${green}./scripts/build.sh${reset}, test with ${green}./scripts/test.sh${reset}, verify snapshots with ${green}./scripts/snapshots.sh verify${reset}, or launch with ${green}./scripts/run.sh${reset}."
