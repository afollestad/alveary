# GitHub comment attachments

Alveary uploads media into comment and review drafts through authenticated `gh api` calls. GitHub CLI 2.99.0 or newer is the supported minimum for attachments; other GitHub features retain their existing requirements. No extension, browser cookies, or Full Disk Access grant is needed.

## Contract and owners

`DefaultGitHubAttachmentUploadService` owns the transport and per-batch compatibility check. `GitHubAttachmentFile` owns supported formats, validation, and Markdown generation. `GitHubAttachmentUploadError` owns compatibility and failure classification. `PullRequestsViewModel+Attachments.swift` owns draft placeholders, partial results, and image seeding.

Each nonempty batch:

1. Validates every file as readable, nonempty, and regular, including size and format.
2. Resolves `gh` and checks `gh --version` against 2.99.0. Checks run again on retry so an upgrade needs no app restart.
3. Fetches `GET https://api.github.com/repos/{owner}/{repo}` and requires a positive numeric `id` plus `permissions.push: true`.
4. Sequentially sends `POST https://uploads.github.com/user-attachments/assets`, with the file as the raw body, `Content-Type: application/octet-stream`, and `Accept: application/vnd.github+json`.
5. Supplies query parameters `name` (basename), `content_type` (media MIME type), and `repository_id` (numeric ID). `gh api --input` streams the file, sets Content-Length, and puts field arguments into the query string, encoding punctuation in filenames.
6. Decodes JSON `{ "url": "https://github.com/user-attachments/assets/<uuid>" }`. Alveary requires an HTTPS GitHub asset URL with a UUID, without credentials, port, query, or fragment.

All calls explicitly select `github.com`; Enterprise hosts are outside the current app's PR model. `gh` supplies credentials, including authentication for `uploads.github.com`. Native uploads accept OAuth, classic PAT, and fine-grained PAT credentials; GitHub enforces repository write access and token permissions. App/installation tokens are not supported by native uploads.

The supported extensions are PNG, JPG, JPEG, GIF, WebP, SVG, MP4, MOV, and WebM, case-insensitively. Images allow up to 10 MiB, videos up to 100 MiB; GitHub may enforce a lower video limit for the account. Other files are rejected. The picker derives its allowed types from the same source; dropped files still undergo service validation.

Images produce escaped Markdown image references using the filename as alt text. Videos produce bare URLs in separate paragraphs. Successful images seed the existing image cache before draft references appear. Repository registration and signed-image URL resolution remain necessary for fetching private attachments later.

Calls use null stdin and 64 KiB output limits; metadata/version calls allow 20 seconds, each upload 300 seconds. Truncated or malformed success output is rejected. Uploads stop on the first failure and never automatically retry. The batch result retains confirmed uploads on failure or cancellation; drafts retain those links and withdraw remaining placeholders. A cancelled request can reach GitHub without returning a URL, so its remote outcome may be unknown. GitHub provides no attachment-delete operation; discarding a draft does not undo uploaded assets.

## Upstream references

The standalone upload endpoint is visible in GitHub CLI's implementation, but is not separately documented as a public REST API. Alveary calls it directly because `--attach` posts or edits content and cannot supply upload-only links for inline reviews and review summaries.

The source baseline is **v2.99.0**, released September 1, 2026:

- [Release and native attachment feature](https://github.com/cli/cli/releases/tag/v2.99.0)
- [Uploader, credentials, permissions, and HTTP errors](https://github.com/cli/cli/blob/v2.99.0/internal/attachments/client.go)
- [File formats, size limits, and Markdown](https://github.com/cli/cli/blob/v2.99.0/internal/attachments/userasset.go)
- [Partial uploads and irreversible assets](https://github.com/cli/cli/blob/v2.99.0/internal/attachments/attach.go)
- [Upload host mapping](https://github.com/cli/cli/blob/v2.99.0/internal/ghinstance/host.go)
- [`gh api --input` query/body and Content-Length handling](https://github.com/cli/cli/blob/v2.99.0/pkg/cmd/api/api.go)
- [Authentication header handling](https://github.com/cli/cli/blob/v2.99.0/api/http_client.go) and [host normalization in its pinned go-gh v2.13.0 dependency](https://github.com/cli/go-gh/blob/v2.13.0/pkg/auth/auth.go)

2.99.0 is Alveary's tested support floor, not a claim that `gh api --input` first appeared in that release. Numeric release components are compared; ordinary build suffixes are accepted. Malformed or failed version probes produce a compatibility-check error. Missing-command/flag failures backstop the check for wrappers or incompatible builds. HTTP failures do not imply an old CLI.

## Troubleshooting

1. Confirm the executable Alveary resolved, not just the shell's preferred binary. Compatibility errors include its path. The shared `DefaultExecutablePathResolver` caches successful paths; upgrading that binary is detected on the next attempt. If moving between installation locations, restart the app. Compare `command -v gh` and the resolved binary's `--version`.
2. Upgrade an old CLI with `brew upgrade gh` for Homebrew, or follow [GitHub CLI installation instructions](https://cli.github.com/). A version-probe failure should be investigated at the reported executable path.
3. Run `gh auth status --hostname github.com`. Use Git settings or `gh auth login --hostname github.com` to sign in. Do not copy tokens or enable verbose HTTP logging in bug reports.
4. Run `gh api --hostname github.com repos/OWNER/REPO --jq '{id,permissions}'`. Confirm the target repository and write access. Review fine-grained token repository selection and permissions if access disagrees with the browser.
5. Separate authentication (401), permission (403), unavailable repository/endpoint (404), validation (422), and rate-limit (429 or a rate-limit 403) errors. A 404 can conceal insufficient token access; if write access is confirmed, compare the endpoint contract with upstream. A malformed successful response can indicate API drift.
6. Retry only failed/unattempted files. Preserve already returned links. Include the CLI version/path, HTTP status and redacted error, file extension/size, and whether repository lookup succeeded in a bug report.

### Manual upload reproduction

**This command uploads a real asset; it does not publish a comment and the asset cannot be deleted through this API.** Use an intended attachment in a repository you control, and retain the returned URL for the draft. Supply the MIME type matching the file.

```sh
gh_bin='/absolute/path/to/gh'
attachment_repo='OWNER/REPO'
attachment_file='/absolute/path/to/screenshot.png'
"$gh_bin" --version
"$gh_bin" auth status --hostname github.com
attachment_repo_id=$("$gh_bin" api --hostname github.com "repos/$attachment_repo" --jq '.id')
"$gh_bin" api --hostname github.com --method POST \
  https://uploads.github.com/user-attachments/assets \
  --input "$attachment_file" \
  --header 'Content-Type: application/octet-stream' \
  --header 'Accept: application/vnd.github+json' \
  --raw-field "name=${attachment_file##*/}" \
  --raw-field 'content_type=image/png' \
  --field "repository_id=$attachment_repo_id"
```

### Repair checklist

- Compare the version-pinned sources above with the installed and latest CLI implementations: endpoint host/path, credential support, query parameters, headers, response URL, formats, and error statuses.
- Update transport, validation, compatibility requirements, picker formats, and response/error fixtures together. Keep credentials inside `gh`; do not restore the removed extension or browser-cookie flow.
- Re-run focused attachment service and view-model tests, then relevant PR composer/list/review snapshots. Verify image/video drafts and partial failures; changing the transport must preserve inline-review workflows.
- Update this source baseline and README requirements when changing the contract or minimum supported version.
