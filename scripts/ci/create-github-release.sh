#!/bin/sh
set -eu

if [ ! -s "$RELEASE_NOTES_PATH" ]; then
  echo "error: release notes file is missing or empty: $RELEASE_NOTES_PATH" >&2
  exit 1
fi

gh release create "$TAG_NAME" \
  "$ZIP_PATH#Alveary.app.zip" \
  --repo "$GITHUB_REPOSITORY" \
  --title "Alveary ${VERSION}" \
  --notes-file "$RELEASE_NOTES_PATH"
