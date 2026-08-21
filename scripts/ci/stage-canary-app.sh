#!/bin/sh
set -eu

# Canary artifacts upload the exported bundle itself rather than a ZIP of it, so
# a download is a runnable app instead of an archive holding another archive.
# Two properties of `actions/upload-artifact` shape this script, and both fail
# silently rather than loudly:
#
# It follows symlinks and stores a copy of each target, which would replace a
# link with a duplicate file and invalidate the code signature. Release and dry
# run modes ZIP the bundle first and are immune, so the guard below runs only for
# canaries. Fail here rather than ship a silently broken bundle.
#
# It also roots the archive at the uploaded path, dropping that directory's own
# name. Uploading `Alveary.app` therefore stores `Contents/` at the top level,
# and macOS expands a single-entry archive in place, leaving a bare `Contents/`
# folder that is not a bundle. So stage the app alone in a directory and upload
# that instead: `Alveary.app` becomes the archive's sole top-level entry, and
# both `gh run download` and a browser download reconstitute the bundle.
app_path="$EXPORT_PATH/${APP_NAME}.app"

symlinks=$(find "$app_path" -type l)
if [ -n "$symlinks" ]; then
  echo "error: canary uploads flatten symlinks, but ${APP_NAME}.app contains:" >&2
  echo "$symlinks" >&2
  echo "hint: ZIP the bundle for canaries too, or stop embedding the linked payload." >&2
  exit 1
fi

# A fresh directory rather than a fixed one, so nothing another step wrote under
# `$RELEASE_PATH` — the dSYM ZIP built before this — can become a second
# top-level entry. Copied rather than moved so `$EXPORT_PATH` stays intact.
mkdir -p "$RELEASE_PATH"
stage_path=$(mktemp -d "$RELEASE_PATH/canary.XXXXXX")
ditto "$app_path" "$stage_path/${APP_NAME}.app"
echo "app_dir=$stage_path" >> "$GITHUB_OUTPUT"

echo "No symlinks in ${APP_NAME}.app; staged at $stage_path for upload."
