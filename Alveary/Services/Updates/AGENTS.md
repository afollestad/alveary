## App Updates

These instructions cover update-checking, release metadata, download, staging, and install helpers under `Alveary/Services/Updates/`.

- Runtime update checks use the GitHub CLI so private GitHub Releases work through the user's existing `gh` auth.
- Downloads use `gh auth token`, then stream the GitHub release asset API URL with authenticated `URLSession` requests so progress can be reported while private repositories still work.
- Keep update ZIP downloads non-cached so progress reflects the current GitHub asset instead of a reused local response.
- Require GitHub release asset SHA-256 digests for installable updates, and verify the downloaded ZIP digest before staging.
- Keep missing or unauthenticated `gh` states explicit in Settings; do not silently fall back to unauthenticated release HTTP.
- Keep the release artifact contract aligned with CI: GitHub Releases publish `Alveary.app.zip`, which contains `Alveary.app`.
- Read the running app version from bundle metadata at runtime. `project.yml` is the build-time source only.
- Store updater-owned downloads, staged metadata, helper logs, and failure markers under `SessionComponent.appSupportDirectory/Updates`.
- Quarantine staged metadata before relaunching an installed update, and preserve it when rollback is required.
- Treat equal or older managed staged state as completed cleanup so updates installed by older helpers do not surface a false download failure.
- Resolve and validate staged bundle paths before cleanup; only remove the exact updater-owned child directory under `Updates/Staged`.
