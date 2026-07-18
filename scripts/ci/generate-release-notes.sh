#!/bin/bash
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PREVIOUS_TAG:?PREVIOUS_TAG is required}"
: "${RELEASE_NOTES_BASE:?RELEASE_NOTES_BASE is required}"
: "${TAG_NAME:?TAG_NAME is required}"
: "${RELEASE_NOTES_PATH:?RELEASE_NOTES_PATH is required}"

copilot_executable=${COPILOT_EXECUTABLE:-copilot}
candidate_commit_count=$(git log \
  --format='%s' \
  --extended-regexp \
  --invert-grep \
  --grep='^Release Alveary v[0-9]+\.[0-9]+\.[0-9]+$' \
  "$RELEASE_NOTES_BASE..HEAD" | wc -l | tr -d '[:space:]')
expected_full_changelog="**Full Changelog**: https://github.com/${GITHUB_REPOSITORY}/compare/${PREVIOUS_TAG}...${TAG_NAME}"

prompt=$(printf '%s\n' \
  "Review the git log and commit diffs in range ${RELEASE_NOTES_BASE}..HEAD and write a concise Markdown bullet list summarizing all code changes made since release ${PREVIOUS_TAG}." \
  "Exclude version-release commits and any other commits that are not relevant to a user-facing changelog." \
  "End every bullet with the short commit hash as a Markdown link in parentheses, followed by the GitHub username of the commit author, using this exact suffix format: ([\`short-hash\`](https://github.com/${GITHUB_REPOSITORY}/commit/full-hash)) by @username." \
  "Begin directly with the first bullet. Do not add a heading, introduction, or other content before it, and keep every bullet on one line." \
  "The final line must exactly equal the following text, with no trailing punctuation:" \
  "$expected_full_changelog" \
  "Use the write tool to write the complete final output directly to this Markdown file: ${RELEASE_NOTES_PATH}" \
  "Write nothing to that file except the bullet list and Full Changelog link. Do not use a code fence." \
  "Do not modify any other files, and do not return the release notes in your response after writing the file.")

rm -f "$RELEASE_NOTES_PATH"
if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "error: checkout is not clean before release-note generation" >&2
  exit 1
fi

if (( candidate_commit_count > 0 )); then
  "$copilot_executable" --silent --no-ask-user --no-custom-instructions \
    --allow-tool='shell(git log:*)' \
    --allow-tool='shell(git show:*)' \
    --allow-tool=write \
    -p "$prompt" > /dev/null
else
  printf '%s\n' "$expected_full_changelog" > "$RELEASE_NOTES_PATH"
fi

if [[ "$(git status --porcelain --untracked-files=all)" != "?? .release-notes.md" ]]; then
  echo "error: release-note generation modified unexpected workspace files" >&2
  exit 1
fi

actual_final_line=$(awk 'NF { line = $0 } END { print line }' "$RELEASE_NOTES_PATH")
bullet_line_count=$(awk '/^- / { count += 1 } END { print count + 0 }' "$RELEASE_NOTES_PATH")
footer_line_count=$(awk -v full_changelog="$expected_full_changelog" '$0 == full_changelog { count += 1 } END { print count + 0 }' "$RELEASE_NOTES_PATH")
invalid_body_line_count=$(awk \
  -v full_changelog="$expected_full_changelog" '
  NF && $0 != full_changelog && $0 !~ /^- / { count += 1 }
  END { print count + 0 }
' "$RELEASE_NOTES_PATH")

if [[ "$actual_final_line" != "$expected_full_changelog" ||
      "$footer_line_count" -ne 1 ||
      "$invalid_body_line_count" -ne 0 ||
      ( "$candidate_commit_count" -gt 0 && "$bullet_line_count" -eq 0 ) ||
      ( "$candidate_commit_count" -eq 0 && "$bullet_line_count" -ne 0 ) ]]; then
  echo "error: Copilot generated release notes outside the required Markdown format" >&2
  exit 1
fi
