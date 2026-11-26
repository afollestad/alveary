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
  "Review the git log and commit diffs in range ${RELEASE_NOTES_BASE}..HEAD and write a short Markdown list of the user-facing changes made since release ${PREVIOUS_TAG}." \
  "Include only changes a user of the app would notice: features, user interface, behavior, performance, and bug fixes." \
  "Exclude version-release commits, continuous integration and workflow changes, tests, snapshots, internal refactors, dependency bumps, documentation, and agent-guidance edits." \
  "Summarize features, not commits: write one bullet per feature or notable improvement, and merge every commit that builds, extends, or fixes it into that bullet. For example, commits that add a feature, polish its interface, and fix its early bugs become a single 'Add ...' bullet." \
  "Merge scattered fixes and reliability work in one area into one broad bullet, such as 'Improve sync reliability.', instead of listing each fix." \
  "Write each summary as one short sentence in the imperative mood, like a commit subject: 'Add', 'Improve', 'Fix', never 'Added', 'Improved', 'Fixed', or 'Adding'." \
  "Use plain language a user understands. Name menu items and settings as the app shows them, but never source code, types, frameworks, or APIs." \
  "Write every bullet at the start of its line as a hyphen and a space followed by the summary, with no headings, theme groups, nested bullets, bold, or italics." \
  "End every bullet with the short commit hash of each merged commit as a Markdown link, comma-separated inside one set of parentheses, followed by the GitHub username of the commit authors, using this exact suffix format: ([\`short-hash\`](https://github.com/${GITHUB_REPOSITORY}/commit/full-hash), [\`short-hash\`](https://github.com/${GITHUB_REPOSITORY}/commit/full-hash)) by @username" \
  "Separate multiple authors with commas after 'by'." \
  "If no commit in the range is user-facing, write exactly one bullet that summarizes the internal work and links those commits." \
  "Begin directly with the first bullet. Do not add a heading, introduction, or other content before it, and keep every bullet on one line." \
  "Separate the Full Changelog footer from the list with a blank line. The final line must exactly equal the following text, with no trailing punctuation:" \
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

# Every non-blank line must be a top-level bullet or the footer, so headings and nested bullets fail as
# invalid lines, and a bold theme-group header fails as a bullet without commit links.
validation_counts=$(awk -v full_changelog="$expected_full_changelog" '
  $0 == full_changelog { footer_count += 1; next }
  !NF { next }
  /^- [^[:space:]]/ {
    if ($0 !~ /\]\(http/) { unlinked_count += 1 }
    bullet_count += 1
    next
  }
  { invalid_count += 1 }
  END { print bullet_count + 0, footer_count + 0, invalid_count + 0, unlinked_count + 0 }
' "$RELEASE_NOTES_PATH")
read -r bullet_count footer_line_count invalid_body_line_count unlinked_bullet_count <<< "$validation_counts"

if [[ "$actual_final_line" != "$expected_full_changelog" ||
      "$footer_line_count" -ne 1 ||
      "$invalid_body_line_count" -ne 0 ||
      "$unlinked_bullet_count" -ne 0 ||
      ( "$candidate_commit_count" -gt 0 && "$bullet_count" -eq 0 ) ||
      ( "$candidate_commit_count" -eq 0 && "$bullet_count" -ne 0 ) ]]; then
  echo "error: Copilot generated release notes outside the required Markdown format" >&2
  echo "candidate commits: ${candidate_commit_count}, bullets: ${bullet_count}," \
    "footers: ${footer_line_count}, invalid lines: ${invalid_body_line_count}," \
    "bullets without commit links: ${unlinked_bullet_count}" >&2
  echo "generated ${RELEASE_NOTES_PATH}:" >&2
  cat "$RELEASE_NOTES_PATH" >&2
  exit 1
fi

# Without a blank line, Markdown treats the footer as a continuation of the last bullet.
normalized_notes_path=$(mktemp)
trap 'rm -f "$normalized_notes_path"' EXIT
awk -v full_changelog="$expected_full_changelog" '
  $0 == full_changelog && NR > 1 && previous_nonblank { print "" }
  { print; previous_nonblank = NF > 0 }
' "$RELEASE_NOTES_PATH" > "$normalized_notes_path"
cat "$normalized_notes_path" > "$RELEASE_NOTES_PATH"
