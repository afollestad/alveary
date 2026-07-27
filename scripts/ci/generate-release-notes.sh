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
  "Review the git log and commit diffs in range ${RELEASE_NOTES_BASE}..HEAD and write a Markdown list of the user-facing changes made since release ${PREVIOUS_TAG}." \
  "Include only changes a user of the app would notice: features, user interface, behavior, performance, and bug fixes." \
  "Exclude version-release commits, continuous integration and workflow changes, tests, snapshots, internal refactors, dependency bumps, documentation, and agent-guidance edits." \
  "Group the changes by feature or theme. Each group is a top-level bullet whose entire content is the bold theme name, like this: - **Theme name**" \
  "Under each group, write child bullets that start with exactly two spaces, then a hyphen and a space, then the summary wrapped in single asterisks so it renders in italics." \
  "Merge closely related commits into a single child bullet instead of repeating one bullet per commit." \
  "End every child bullet with the short commit hash of each merged commit as a Markdown link, comma-separated inside one set of parentheses, followed by the GitHub username of the commit authors, using this exact suffix format: ([\`short-hash\`](https://github.com/${GITHUB_REPOSITORY}/commit/full-hash), [\`short-hash\`](https://github.com/${GITHUB_REPOSITORY}/commit/full-hash)) by @username" \
  "Separate multiple authors with commas after 'by'." \
  "Every child bullet must sit under a group, and every group must have at least one child bullet." \
  "Put any user-facing change that fits no theme under a final group named - **Other**" \
  "If no commit in the range is user-facing, write exactly one - **Other** group containing a single child bullet that summarizes the internal work and links those commits." \
  "Begin directly with the first group bullet. Do not add a heading, introduction, or other content before it, and keep every bullet on one line." \
  "The final line must exactly equal the following text, with no trailing punctuation:" \
  "$expected_full_changelog" \
  "Use the write tool to write the complete final output directly to this Markdown file: ${RELEASE_NOTES_PATH}" \
  "Write nothing to that file except the grouped bullet list and Full Changelog link. Do not use a code fence." \
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

# One stateful pass: group and child bullets are only valid relative to each other, so orphan
# children and childless groups cannot be counted by independent line-matching passes.
# The child pattern accepts two-or-more leading spaces rather than an exact count so a model
# that indents four spaces still passes; both nest correctly in GitHub-flavored Markdown.
validation_counts=$(awk -v full_changelog="$expected_full_changelog" '
  $0 == full_changelog { footer_count += 1; next }
  !NF { next }
  /^- [*][*].+[*][*]$/ {
    if (open_group && children_in_group == 0) { invalid_count += 1 }
    group_count += 1
    open_group = 1
    children_in_group = 0
    next
  }
  /^  +- [*].+[*]/ {
    if (!open_group) { invalid_count += 1 }
    if ($0 !~ /\]\(http/) { unlinked_count += 1 }
    child_count += 1
    children_in_group += 1
    next
  }
  { invalid_count += 1 }
  END {
    if (open_group && children_in_group == 0) { invalid_count += 1 }
    print group_count + 0, child_count + 0, footer_count + 0, invalid_count + 0, unlinked_count + 0
  }
' "$RELEASE_NOTES_PATH")
read -r group_count child_count footer_line_count invalid_body_line_count unlinked_child_count <<< "$validation_counts"

if [[ "$actual_final_line" != "$expected_full_changelog" ||
      "$footer_line_count" -ne 1 ||
      "$invalid_body_line_count" -ne 0 ||
      "$unlinked_child_count" -ne 0 ||
      ( "$candidate_commit_count" -gt 0 && ( "$group_count" -eq 0 || "$child_count" -eq 0 ) ) ||
      ( "$candidate_commit_count" -eq 0 && ( "$group_count" -ne 0 || "$child_count" -ne 0 ) ) ]]; then
  echo "error: Copilot generated release notes outside the required Markdown format" >&2
  echo "candidate commits: ${candidate_commit_count}, groups: ${group_count}, children: ${child_count}," \
    "footers: ${footer_line_count}, invalid lines: ${invalid_body_line_count}," \
    "children without commit links: ${unlinked_child_count}" >&2
  echo "generated ${RELEASE_NOTES_PATH}:" >&2
  cat "$RELEASE_NOTES_PATH" >&2
  exit 1
fi
