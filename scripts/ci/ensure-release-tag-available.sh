#!/bin/sh
set -eu

if git ls-remote --exit-code --tags origin "refs/tags/${TAG_NAME}" >/dev/null 2>&1; then
  echo "error: tag ${TAG_NAME} already exists" >&2
  exit 1
fi
