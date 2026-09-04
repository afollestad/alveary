## GitHub CLI

These instructions cover `Alveary/Services/Git/GitHubCLI/` — `gh` authentication (`GitHubCLIService`) and native comment-attachment uploads through `gh api`. The `gh api` pull-request adapter is a separate scope: `Alveary/Services/PullRequests/GitHub/AGENTS.md`.

- `gh auth login --web` does not auto-open the browser without a TTY. GitHub auth flows in the app must continue parsing the emitted URL/code and opening the browser explicitly.
- **`GitHubAttachmentImageURLResolver` mints anonymously fetchable attachment-image URLs.** `github.com/user-attachments` assets are served only to a signed-in browser session — always in private repositories, and even public ones until the embedding content is saved and propagated — so the app cannot fetch them directly. `gh api /markdown` with a repository `context` rewrites such URLs to `private-user-images.githubusercontent.com` links carrying a ~5-minute JWT that downloads with no credentials (without `context` no rewrite happens). The resolver tries recently registered repositories most-recent-first (PR panes register on open), caches mints for 3 minutes, and feeds `AppMarkdownImageStore.remoteFallbackURLProvider`; bytes then persist in the shared disk cache under the original URL's key, so the mint happens at most once per asset.

- **Keep attachments on the native `gh api` upload path; do not restore extensions or browser-cookie access.** `GitHubAttachmentUploadService` owns the transport contract; `docs/github-attachments.md` at the repo root records upstream sources and troubleshooting.
- **Keep picker formats aligned with `GitHubAttachmentFile.supportedExtensions`.** Service validation also covers dropped files; the UI cannot substitute for it.
