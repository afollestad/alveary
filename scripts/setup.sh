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

echo "Setup complete. Next steps:"
echo "  1. If you want to view the project in XCode: `open Skep.xcodeproj`"
echo "  2. Re-run 'xcodegen generate' any time you change project structure or dependencies, then re-open Skep.xcodeproj."
