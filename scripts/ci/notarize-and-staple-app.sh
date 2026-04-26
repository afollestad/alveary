#!/bin/sh
set -eu

app_path="$EXPORT_PATH/${APP_NAME}.app"
key_path="$RUNNER_TEMP/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
notary_zip="$RUNNER_TEMP/${APP_NAME}-notary.zip"

printf '%s' "$APP_STORE_CONNECT_API_KEY_P8_BASE64" | base64 --decode > "$key_path"
chmod 600 "$key_path"
ditto -c -k --keepParent "$app_path" "$notary_zip"

xcrun notarytool submit "$notary_zip" \
  --key "$key_path" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
