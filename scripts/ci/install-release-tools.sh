#!/bin/sh
set -eu

install_brew_formula() {
  formula=$1
  if ! brew list --formula "$formula" >/dev/null 2>&1; then
    brew install "$formula"
  fi
}

install_brew_formula xcodegen
install_brew_formula xcsift
install_brew_formula swiftlint
install_brew_formula mint

if ! command -v knit-cli >/dev/null 2>&1; then
  mint install cashapp/knit knit-cli
fi
