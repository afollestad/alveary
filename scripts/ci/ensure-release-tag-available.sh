#!/bin/sh
set -eu

status=0
git ls-remote --exit-code --tags origin "refs/tags/${TAG_NAME}" >/dev/null 2>&1 || status=$?

if [ "$status" -eq 0 ]; then
  echo "error: tag ${TAG_NAME} already exists" >&2
  exit 1
fi

if [ "$status" -ne 2 ]; then
  echo "error: failed to check tag ${TAG_NAME}" >&2
  exit 1
fi
