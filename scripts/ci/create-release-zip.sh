#!/bin/sh
set -eu

mkdir -p "$RELEASE_PATH"
zip_path="$RELEASE_PATH/Alveary.app.zip"
ditto -c -k --keepParent "$EXPORT_PATH/${APP_NAME}.app" "$zip_path"
echo "zip_path=$zip_path" >> "$GITHUB_OUTPUT"
