## App Updates

These instructions cover update-checking, release metadata, download, staging, and install helpers under `Alveary/Services/Updates/`.

- Runtime update checks and downloads use the GitHub CLI so private GitHub Releases work through the user's existing `gh` auth.
- Keep missing or unauthenticated `gh` states explicit in Settings; do not silently fall back to unauthenticated release HTTP.
- Keep the release artifact contract aligned with CI: GitHub Releases publish `Alveary.app.zip`, which contains `Alveary.app`.
- Read the running app version from bundle metadata at runtime. `project.yml` is the build-time source only.
- Store updater-owned downloads, staged metadata, helper logs, and failure markers under `SessionComponent.appSupportDirectory/Updates`.
