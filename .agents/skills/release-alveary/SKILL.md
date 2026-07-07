---
name: release-alveary
description: Prepare, dry-run, and trigger Alveary direct-download macOS releases. Use when the user asks to release Alveary, run a release dry run, bump the app version, create a patch/minor/major release, trigger release CI, or publish the signed and notarized GitHub Release ZIP.
---

# Release Alveary

## Overview

Release Alveary by bumping the app version in `project.yml`, committing the bump, pushing it to `main`, and watching GitHub Actions create the tag and notarized ZIP release. CI owns tag creation, signing, notarization, stapling, packaging, and GitHub Release upload.

## Workflow

1. Start from the repo root and read `AGENTS.md`.
2. Confirm `git status --short --branch` is clean. Stop if unrelated changes exist.
3. Confirm the local branch is `main` and up to date with `origin/main`.
4. Ask which release bump to make when the user did not specify one: `patch`, `minor`, or `major`.
5. Read these Alveary app version build settings from `project.yml`:
   - `MARKETING_VERSION`
   - `CURRENT_PROJECT_VERSION`
6. Bump the version:
   - patch: `X.Y.Z` -> `X.Y.(Z + 1)`
   - minor: `X.Y.Z` -> `X.(Y + 1).0`
   - major: `X.Y.Z` -> `(X + 1).0.0`
7. Increment `CURRENT_PROJECT_VERSION` by 1.
8. Run `xcodegen generate`.
9. Verify build settings and the built app metadata.
10. Commit only the release bump and generated project changes that are meant to be tracked.
11. Push `main`.
12. Watch the `Release` workflow and report the run URL, tag, and release URL.

## Commands

Use a structured parser or a tightly scoped script to update only the two version keys. Do not edit secret values or release workflow credentials during a normal version bump.

```sh
git fetch origin main --tags
git status --short --branch
```

After editing `project.yml`:

```sh
xcodegen generate
xcodebuild -project Alveary.xcodeproj -scheme Alveary -configuration Release -showBuildSettings | rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|INFOPLIST_FILE'
```

Build and inspect the app metadata before committing:

```sh
xcodebuild -project Alveary.xcodeproj -scheme Alveary -configuration Release -destination 'platform=macOS' -derivedDataPath .build/xcode build
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' .build/xcode/Build/Products/Release/Alveary.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' .build/xcode/Build/Products/Release/Alveary.app/Contents/Info.plist
```

Commit with the appropriate trailer from the root `AGENTS.md`:

```sh
git add project.yml
git commit -m "Release Alveary vX.Y.Z" -m "Co-authored-by: <agent> <email>"
git push origin main
```

Watch CI:

```sh
gh run list --workflow Release --branch main --limit 5
gh run watch <run-id>
gh release view vX.Y.Z --web
```

Dry run CI without publishing:

```sh
gh workflow run Release --ref main
gh run list --workflow Release --branch main --limit 5
gh run watch <run-id>
```

## Rules

- Keep releases tag-driven by CI. Do not create or push the release tag locally.
- Use manual `workflow_dispatch` runs only for dry runs; they must upload an Actions artifact and must not create tags or GitHub Releases.
- Keep the release ZIP as `Alveary.app` inside GitHub Release asset `Alveary.app.zip`; do not add DMG or PKG packaging.
- Keep CI implementation details in `scripts/ci/*`; keep `.github/workflows/release.yml` as orchestration.
- Do not print, commit, or rewrite signing/notarization secrets.
- Stop if the target release tag already exists.
- Stop if `MARKETING_VERSION` is not `X.Y.Z`.
- Stop if `CURRENT_PROJECT_VERSION` is not an integer.
