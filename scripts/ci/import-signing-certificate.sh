#!/bin/sh
set -eu

certificate_path="$RUNNER_TEMP/developer-id-application.p12"
printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate_path"

security create-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$certificate_path" \
  -k "$KEYCHAIN_PATH" \
  -P "$MACOS_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/xcodebuild
security list-keychains -d user -s "$KEYCHAIN_PATH"
security default-keychain -s "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$MACOS_KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH"
