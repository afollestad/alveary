#!/bin/sh
set -eu

app_path="$EXPORT_PATH/${APP_NAME}.app"
info_plist="$app_path/Contents/Info.plist"
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")

if [ "$actual_version" != "$VERSION" ] || [ "$actual_build" != "$BUILD" ]; then
  echo "error: exported app has version ${actual_version} (${actual_build}), expected ${VERSION} (${BUILD})" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"

microphone_usage=$(/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$info_plist" 2>/dev/null || true)
if [ -z "$microphone_usage" ]; then
  echo "error: exported app is missing NSMicrophoneUsageDescription" >&2
  exit 1
fi

attributions_path="$app_path/Contents/Resources/VoiceInputAttributions.txt"
if [ ! -s "$attributions_path" ]; then
  echo "error: exported app is missing the bundled voice-input attributions" >&2
  exit 1
fi

voice_descriptor_path="$app_path/Contents/Resources/VoiceInputModelDescriptor.json"
source_voice_descriptor="$repository_root/Alveary/Resources/VoiceInputModelDescriptor.json"
expected_descriptor_digest=$(tr -d '[:space:]' < "$repository_root/Config/VoiceInputModelDescriptor.sha256")
if [ ! -s "$voice_descriptor_path" ]; then
  echo "error: exported app is missing the bundled voice-model descriptor" >&2
  exit 1
fi
actual_descriptor_digest=$(shasum -a 256 "$voice_descriptor_path" | awk '{print $1}')
if [ "$actual_descriptor_digest" != "$expected_descriptor_digest" ]; then
  echo "error: exported voice-model descriptor digest does not match the release pin" >&2
  exit 1
fi
python3 - "$voice_descriptor_path" "$source_voice_descriptor" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    exported = json.load(file)
with open(sys.argv[2], encoding="utf-8") as file:
    source = json.load(file)
if exported.get("revision") != source.get("revision"):
    raise SystemExit("error: exported voice-model descriptor revision does not match the release pin")
if len(exported.get("artifacts", [])) != 14:
    raise SystemExit("error: exported voice-model descriptor does not contain 14 artifacts")
PY

temp_root=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
entitlements_plist=$(mktemp "$temp_root/alveary-entitlements.XXXXXX")
trap 'rm -f "$entitlements_plist"' EXIT
codesign --display --entitlements "$entitlements_plist" --xml "$app_path" 2>/dev/null

audio_input=$(
  /usr/libexec/PlistBuddy \
    -c 'Print :com.apple.security.device.audio-input' \
    "$entitlements_plist" \
    2>/dev/null || true
)
if [ "$audio_input" != "true" ]; then
  echo "error: exported app is missing the signed audio-input entitlement" >&2
  exit 1
fi

if /usr/libexec/PlistBuddy \
  -c 'Print :com.apple.security.network.client' \
  "$entitlements_plist" \
  >/dev/null 2>&1; then
  echo "error: exported app unexpectedly has the network-client entitlement" >&2
  exit 1
fi

executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")
executable_path="$app_path/Contents/MacOS/$executable_name"
architectures=$(lipo -archs "$executable_path")

for required_architecture in arm64 x86_64; do
  case " $architectures " in
    *" $required_architecture "*) ;;
    *)
      echo "error: exported app executable is missing the $required_architecture slice (found: $architectures)" >&2
      exit 1
      ;;
  esac
done
