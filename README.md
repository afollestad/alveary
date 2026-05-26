# Alveary

_An alveary is a place where bees are kept, including a beehive or apiary enclosure._

Alveary is a native macOS app for orchestrating AI coding agents in parallel. Inspired by Conductor and Codex, and built in Swift with help from the agents themselves.

See the backlog/roadmap [here](https://github.com/users/afollestad/projects/3)!

# Development

## Setup

Alveary is built with XcodeGen, `xcsift`, SwiftLint, and Needle.

Run the bootstrap script once per clone:

```sh
./scripts/setup.sh
```

It installs the required CLI tools via Homebrew (including `xcsift` for agent-friendly TOON `xcodebuild` output), generates `Alveary.xcodeproj`, and configures the repo-local Git hooks so commits touching Swift files run `swiftlint` automatically.

## Build, Test, and Run

Generate the Xcode project after project-structure changes:

```sh
xcodegen generate
```

Build the app:

```sh
./scripts/build.sh
```

Run the app:

```sh
./scripts/run.sh
```

Force a fresh build before launching:

```sh
./scripts/run.sh -b
```

The wrapper scripts share the same build output path as the underlying `xcodebuild` commands.

Run the full test suite:

```sh
./scripts/test.sh
```

Run a focused test class:

```sh
./scripts/test.sh AlvearyTests/AppDelegateTests
```

## Snapshot Tests

Verify the full snapshot suite:

```sh
./scripts/snapshots.sh verify
```

Verify or record a focused snapshot test:

```sh
./scripts/snapshots.sh verify AlvearyTests/SnapshotTests/testSidebarViewPopulated
./scripts/snapshots.sh record AlvearyTests/SnapshotTests/testSidebarViewPopulated
```

When no test identifier is provided, `./scripts/snapshots.sh` defaults to `AlvearyTests/SnapshotTests`.

## Repo-Local Agent Workflows

Project-local agent workflows live under `.agents`: capability skills in `.agents/skills`, and review, audit, and check workflows in `.agents/checks`. Agent-specific folders such as `.claude/skills`, `.codex/skills`, `.claude/checks`, and `.codex/checks` are symlinks to those canonical directories.

## Releases

Alveary releases are direct-download ZIPs containing `Alveary.app`. The app version lives in `project.yml` under the app target build settings:

```yaml
MARKETING_VERSION: 0.1.0
CURRENT_PROJECT_VERSION: 1
```

Release automation runs from GitHub Actions when a push to `main` changes `MARKETING_VERSION`. CI creates the `vX.Y.Z` tag, signs with Developer ID, notarizes and staples `Alveary.app`, creates `Alveary.zip`, and uploads it to GitHub Releases. Manual workflow runs are dry runs: they sign, notarize, staple, zip, and upload an Actions artifact without creating a tag or GitHub Release. The workflow orchestration lives in `.github/workflows/release.yml`; the implementation scripts live under `scripts/ci/`.

# License

Alveary is licensed under the [GNU General Public License v3.0](LICENSE.md).
