#!/bin/sh
set -eu

# Release builds strip the installed product, so a crash or hang report from a
# shipped binary symbolicates only against the archive's dSYMs. Nothing else
# retains them: the runner is discarded, and recovering them afterwards means
# rebuilding the exact commit on the exact toolchain and byte-matching `__text`
# to find the slide. Package them for every mode that hands out a binary.
dsym_directory="$ARCHIVE_PATH/dSYMs"
app_dsym="$dsym_directory/${APP_NAME}.app.dSYM"
app_binary="$EXPORT_PATH/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

if [ ! -d "$app_dsym" ]; then
  echo "error: archive has no dSYM for ${APP_NAME}.app: $app_dsym" >&2
  echo "hint: Release needs DEBUG_INFORMATION_FORMAT=dwarf-with-dsym; the archive holds:" >&2
  if [ -d "$dsym_directory" ]; then
    ls -1 "$dsym_directory" >&2
  else
    echo "  (no dSYMs directory)" >&2
  fi
  exit 1
fi

# A crash report is matched to its dSYM by UUID alone, so a dSYM from a different
# build reads as "no symbols" months later with nothing left to explain why.
# Space-delimited on one line so the membership test below can bracket each UUID
# with spaces; `dwarfdump` prints one slice per line.
dsym_uuids=$(dwarfdump --uuid "$app_dsym" | awk '{print $2}' | tr '\n' ' ')
app_uuids=$(dwarfdump --uuid "$app_binary" | awk '{print $2}' | tr '\n' ' ')

# POSIX `sh` has no `pipefail` and `set -e` cannot see a failure inside a
# pipeline, so an unreadable binary or dSYM reaches here as an empty list rather
# than an error. Reject that explicitly: an empty app list would walk the loop
# below zero times and report a pass.
if [ -z "$app_uuids" ] || [ -z "$dsym_uuids" ]; then
  echo "error: no UUIDs read for ${APP_NAME} (app: '${app_uuids}', dSYM: '${dsym_uuids}')" >&2
  echo "hint: expected a Mach-O at $app_binary and DWARF inside $app_dsym" >&2
  exit 1
fi

# Every slice being shipped must be covered; the dSYM may carry more when the
# export thinned the binary.
for uuid in $app_uuids; do
  case " $dsym_uuids " in
    *" $uuid "*) ;;
    *)
      echo "error: exported ${APP_NAME} slice $uuid is missing from $app_dsym" >&2
      echo "app:  $app_uuids" >&2
      echo "dSYM: $dsym_uuids" >&2
      exit 1
      ;;
  esac
done

echo "dSYM covers every exported slice: $app_uuids"

mkdir -p "$RELEASE_PATH"
dsym_path="$RELEASE_PATH/${APP_NAME}.dSYMs.zip"
ditto -c -k --keepParent "$dsym_directory" "$dsym_path"
echo "dsym_path=$dsym_path" >> "$GITHUB_OUTPUT"
