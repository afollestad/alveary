#!/bin/sh
set -eu

app_path="$EXPORT_PATH/${APP_NAME}.app"
info_plist="$app_path/Contents/Info.plist"
actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")

if [ "$actual_version" != "$VERSION" ] || [ "$actual_build" != "$BUILD" ]; then
  echo "error: exported app has version ${actual_version} (${actual_build}), expected ${VERSION} (${BUILD})" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
