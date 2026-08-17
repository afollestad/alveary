#!/bin/sh
set -eu

# Canary artifacts upload the exported bundle itself rather than a ZIP of it, so
# `gh run download` writes a runnable app instead of an archive holding another
# archive. `actions/upload-artifact` follows symlinks and stores a copy of each
# target, which would replace a link with a duplicate file and invalidate the
# code signature without failing the upload.
# Release and dry run modes ZIP the bundle first and are immune, so this guard
# only runs for canaries. Fail here rather than ship a silently broken bundle.
app_path="$EXPORT_PATH/${APP_NAME}.app"

symlinks=$(find "$app_path" -type l)
if [ -n "$symlinks" ]; then
  echo "error: canary uploads flatten symlinks, but ${APP_NAME}.app contains:" >&2
  echo "$symlinks" >&2
  echo "hint: ZIP the bundle for canaries too, or stop embedding the linked payload." >&2
  exit 1
fi

echo "No symlinks in ${APP_NAME}.app; safe to upload the bundle verbatim."
