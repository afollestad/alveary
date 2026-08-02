## App Updates

These instructions cover update-checking, release metadata, download, staging, and install helpers under `Alveary/Services/Updates/`.

- Runtime update checks and downloads go through the user's existing `gh` auth (`GitHubCLIAppUpdateReleaseClient`, `GitHubCLIAppUpdateDownloader`) so private GitHub Releases work. Keep missing or unauthenticated `gh` states explicit in Settings; do not silently fall back to unauthenticated release HTTP.
- Historical releases do not need an install asset or digest to contribute notes; validate the release artifact contract only for the highest stable version selected for download. A "cleanup" that filters releases lacking `Alveary.app.zip` would silently delete release history.
- **Keep update ZIP downloads non-cached, in all four places.** The `.ephemeral` session configuration, the request `cachePolicy`, the `no-cache`/`Pragma` headers, and the same headers re-applied on the redirected request all enforce it; the redirect site is the one a simplification pass drops first. A cached response makes progress reflect a stale asset.
- Installable updates require a parseable GitHub release asset SHA-256 digest, verified against the downloaded ZIP before staging — the supply-chain integrity gate.
- Keep the release artifact contract aligned with CI: GitHub Releases publish `Alveary.app.zip`, containing `Alveary.app`.
- Read the running app version from bundle metadata at runtime; `project.yml` is the build-time source only.
- Downloads stream to `FileManager.default.temporaryDirectory/AlvearyUpdates/<uuid>` and the ZIP is deleted after extraction; staged metadata and helper logs live under `AppStorageProfile.updatesDirectory` (`.../Updates`), with staged bundles under `Updates/Staged`.
- Quarantine, rollback, staged-state comparison, and cleanup validation are documented in `DefaultAppUpdateInstaller.swift`, `DefaultAppUpdateStager.swift`, and `AppUpdateInstall.swift`.
