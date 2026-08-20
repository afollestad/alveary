#!/bin/sh
set -eu

if [ ! -s "$RELEASE_NOTES_PATH" ]; then
  echo "error: release notes file is missing or empty: $RELEASE_NOTES_PATH" >&2
  exit 1
fi

# The app ships stripped, so the dSYMs ride along as a second asset: a crash
# report from this build symbolicates against nothing else.
gh release create "$TAG_NAME" \
  "$ZIP_PATH#Alveary.app.zip" \
  "$DSYM_PATH#Alveary.dSYMs.zip" \
  --repo "$GITHUB_REPOSITORY" \
  --title "$TAG_NAME" \
  --notes-file "$RELEASE_NOTES_PATH"
