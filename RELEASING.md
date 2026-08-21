# Releasing Alveary

Alveary ships as a direct-download GitHub Release with an `Alveary.app.zip` asset containing a signed, notarized `Alveary.app`.

## Versioning

The release version and build number live in `project.yml` under the `Alveary` target build settings:

```yaml
MARKETING_VERSION: 0.1.0
CURRENT_PROJECT_VERSION: 1
```

For a normal release, bump `MARKETING_VERSION` to the next `X.Y.Z` value and increment `CURRENT_PROJECT_VERSION`.

## Release Builds

Release automation runs from `.github/workflows/release.yml`.

Every run builds. `scripts/ci/detect-release-version.py` picks one of three modes:

| Mode | Trigger | Notarizes | Result |
| --- | --- | --- | --- |
| `release` | Push to `main` when the current `MARKETING_VERSION` has no `vX.Y.Z` tag on origin | Yes | Tag and GitHub Release |
| `canary` | Any other push to `main` | No | Actions artifact holding `Alveary.app` |
| `dry-run` | Manual `workflow_dispatch` | Yes | Actions artifact holding `Alveary.app.zip` |

- Push-triggered releases create and push the `vX.Y.Z` tag only after validation, signing, notarization, stapling, and ZIP creation succeed.
- GitHub Releases are titled with the `vX.Y.Z` tag name, use generated release notes, and publish the asset as `Alveary.app.zip`.
- A canary build is cancelled when a newer canary supersedes it. Release and dry run builds are never cancelled, and never cancel a canary.

## Canary Builds

Canary builds make every commit on `main` downloadable without publishing anything. They are signed with the same Developer ID certificate and pass the same `scripts/ci/verify-exported-app.sh` checks as a release, but they skip notarization and stapling to keep a notarytool round trip off every merge.

```sh
gh run list --workflow Release --branch main --limit 5
gh run download <run-id> --repo afollestad/alveary -D ~/Downloads
xattr -dr com.apple.quarantine ~/Downloads/Alveary-canary-*/Alveary.app
```

Canaries upload the exported bundle rather than a ZIP of it, so there is no archive inside the download. The artifact is named `Alveary-canary-<version>-<build>-<short-sha>`, so the download says which commit it came from. The `xattr` call clears the quarantine a browser download applies, which Gatekeeper refuses because canaries are not notarized.

Downloading from the Actions page in a browser works too. `actions/upload-artifact` roots its archive at the uploaded path and drops that directory's own name, so uploading the bundle would store a bare `Contents/` folder, and macOS expands a single-entry archive in place. `scripts/ci/stage-canary-app.sh` stages the app alone in a directory and the workflow uploads that instead, making `Alveary.app` the archive's only top-level entry.

The same script fails the build if the bundle ever contains a symlink, because the upload would replace it with a copy of its target and invalidate the signature.

Canary and dry run artifacts both expire after 14 days, and neither is a GitHub Release, so the in-app updater never offers them.

## CI Flow

The workflow performs these high-level steps:

1. Detect the release mode from `project.yml` with `scripts/ci/detect-release-version.py`. This runs in its own `detect` job, because only a job-level concurrency group can read the mode it resolves.
2. For releases, ensure the target tag is available with `scripts/ci/ensure-release-tag-available.sh`.
3. Install release tools and run `xcodegen generate`.
4. Import the Developer ID signing certificate from GitHub Actions secrets.
5. Archive and export the Developer ID app.
6. Verify exported app metadata, signing, entitlements, and architectures.
7. Notarize `Alveary.app`, staple the ticket, and confirm Gatekeeper acceptance. Canary builds skip this step.
8. Create `Alveary.app.zip` with `scripts/ci/create-release-zip.sh`. Canary builds skip this and upload the bundle itself, staged and guarded by `scripts/ci/stage-canary-app.sh`.
9. For releases, generate header-free release notes with `scripts/ci/generate-release-notes.sh`. Notes cover user-facing changes only, grouped into bold theme bullets with indented italic child bullets that merge related commits.
10. Upload the canary bundle or the dry run ZIP as an Actions artifact, or for releases publish the ZIP as a GitHub Release asset with `scripts/ci/create-github-release.sh`.

Keep release implementation logic in `scripts/ci/` and keep the workflow YAML focused on orchestration.

## Secrets

Release CI depends on Developer ID signing and App Store Connect notarization secrets in GitHub Actions. Do not commit certificates, keychain files, API keys, or other signing material.
