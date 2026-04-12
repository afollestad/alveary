#!/bin/sh
set -eu

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
install_brew_formula xcbeautify
install_brew_formula mint

if command -v knit-cli >/dev/null 2>&1; then
  echo "knit-cli already installed"
elif [ -x "$HOME/.mint/bin/knit-cli" ]; then
  echo "knit-cli already installed at $HOME/.mint/bin/knit-cli"
else
  mint install cashapp/knit knit-cli
fi
