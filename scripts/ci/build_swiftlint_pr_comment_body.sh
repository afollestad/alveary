#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 --input <swiftlint-json> --output <markdown-path>" >&2
}

input_path=""
output_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input)
      input_path=$2
      shift 2
      ;;
    --output)
      output_path=$2
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [ -z "$input_path" ] || [ -z "$output_path" ]; then
  usage
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to format SwiftLint JSON output." >&2
  exit 1
fi

repo_root=$(pwd -P)
mkdir -p "$(dirname "$output_path")"

issues_tsv=$(mktemp)
trap 'rm -f "$issues_tsv"' EXIT

jq -r --arg repo_root "$repo_root" '
  def normalized_file:
    (.file // "")
    | if startswith($repo_root + "/") then ltrimstr($repo_root + "/")
      elif startswith("./") then ltrimstr("./")
      else .
      end;

  map(
    select(
      ((.severity // "") | ascii_downcase) == "warning"
      or ((.severity // "") | ascii_downcase) == "error"
    )
    | {
        file: normalized_file,
        severity: ((.severity // "") | ascii_downcase),
        line: (.line // 0),
        character: (.character // 0),
        rule_id: (.rule_id // ""),
        reason: ((.reason // "") | gsub("\\s+"; " ") | gsub("^ +| +$"; ""))
      }
  )
  | sort_by(.file, .severity, .line, .character, .rule_id, .reason)
  | .[]
  | [.file, .severity, (.line | tostring), (.character | tostring), .rule_id, .reason]
  | @tsv
' "$input_path" > "$issues_tsv"

issue_count=$(awk 'END { print NR + 0 }' "$issues_tsv")
if [ "$issue_count" -eq 0 ]; then
  : > "$output_path"
  printf '%s\n' "0"
  exit 0
fi

{
  printf '### SwiftLint issues (%s)\n\n' "$issue_count"

  current_file=""
  while IFS="$(printf '\t')" read -r file_path severity line character rule_id reason; do
    if [ "$file_path" != "$current_file" ]; then
      printf -- '- `%s`\n' "$file_path"
      current_file=$file_path
    fi

    location="L$line"
    if [ "$character" -gt 0 ] 2>/dev/null; then
      location="${location}:C${character}"
    fi

    if [ -n "$rule_id" ]; then
      printf '  - [ ] `%s` `%s` `%s`: %s\n' "$severity" "$location" "$rule_id" "$reason"
    else
      printf '  - [ ] `%s` `%s`: %s\n' "$severity" "$location" "$reason"
    fi
  done < "$issues_tsv"
} > "$output_path"

printf '%s\n' "$issue_count"
