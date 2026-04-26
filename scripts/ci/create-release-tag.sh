#!/bin/sh
set -eu

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git tag -a "$TAG_NAME" -m "Release Alveary ${VERSION}"
git push origin "$TAG_NAME"
