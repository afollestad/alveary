#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --body <markdown-path>" >&2
}

body_path=""
marker='<!-- skep-swiftlint-warnings -->'

while [ "$#" -gt 0 ]; do
  case "$1" in
    --body)
      body_path=$2
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [ -z "$body_path" ]; then
  usage
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh is required to publish SwiftLint PR comments." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to publish SwiftLint PR comments." >&2
  exit 1
fi

if [ -z "${GITHUB_REPOSITORY:-}" ] || [ -z "${GITHUB_EVENT_PATH:-}" ]; then
  echo "error: GITHUB_REPOSITORY and GITHUB_EVENT_PATH are required." >&2
  exit 1
fi

issue_number=$(jq -r '.number // empty' "$GITHUB_EVENT_PATH")
if [ -z "$issue_number" ]; then
  echo "No pull request number found in event payload; skipping SwiftLint PR comment."
  exit 0
fi

body=""
if [ -f "$body_path" ]; then
  body=$(sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' "$body_path")
fi

err_file=$(mktemp)
payload_file=$(mktemp)
comments_file=$(mktemp)
trap 'rm -f "$err_file" "$payload_file" "$comments_file"' EXIT

handle_api_error() {
  if grep -Eq 'HTTP 403|HTTP 404' "$err_file"; then
    echo "::warning::Skipping SwiftLint PR comment because the workflow token cannot write comments for this pull request."
    return 0
  fi

  cat "$err_file" >&2
  return 1
}

if ! gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$issue_number/comments" > "$comments_file" 2> "$err_file"; then
  handle_api_error
  exit $?
fi

existing_comment_id=$(jq -sr --arg marker "$marker" '
  add
  | map(select(.user.type == "Bot" and (.body | contains($marker))))
  | first
  | .id // empty
' "$comments_file")

if [ -z "$body" ]; then
  if [ -n "$existing_comment_id" ]; then
    if ! gh api --method DELETE "repos/$GITHUB_REPOSITORY/issues/comments/$existing_comment_id" > /dev/null 2> "$err_file"; then
      handle_api_error
      exit $?
    fi
  fi

  echo "No SwiftLint issues to comment on."
  exit 0
fi

comment_body=$(printf '%s\n%s\n' "$marker" "$body")
printf '%s' "$comment_body" | jq -Rs '{body: .}' > "$payload_file"

if [ -n "$existing_comment_id" ]; then
  if ! gh api --method PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$existing_comment_id" --input "$payload_file" > /dev/null 2> "$err_file"; then
    handle_api_error
    exit $?
  fi
  exit 0
fi

if ! gh api --method POST "repos/$GITHUB_REPOSITORY/issues/$issue_number/comments" --input "$payload_file" > /dev/null 2> "$err_file"; then
  handle_api_error
  exit $?
fi
