#!/bin/sh
set -eu

gh release create "$TAG_NAME" \
  "$ZIP_PATH#Alveary.app.zip" \
  --repo "$GITHUB_REPOSITORY" \
  --title "Alveary ${VERSION}" \
  --generate-notes
