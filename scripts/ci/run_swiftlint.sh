#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --report <swiftlint-json> --comment-body <markdown-path>" >&2
}

report_path=""
comment_body_path=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --report)
      report_path=$2
      shift 2
      ;;
    --comment-body)
      comment_body_path=$2
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$report_path" || -z "$comment_body_path" ]]; then
  usage
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

mkdir -p "$(dirname "$report_path")" "$(dirname "$comment_body_path")"

lint_exit=0
swiftlint lint --reporter json > "$report_path" || lint_exit=$?
issue_count=$(sh "$repo_root/scripts/ci/build_swiftlint_pr_comment_body.sh" \
  --input "$report_path" \
  --output "$comment_body_path")

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'exit_code=%s\n' "$lint_exit" >> "$GITHUB_OUTPUT"
  printf 'issue_count=%s\n' "$issue_count" >> "$GITHUB_OUTPUT"
fi

if [[ "$lint_exit" -ne 0 ]]; then
  exit "$lint_exit"
fi
