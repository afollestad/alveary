# Alveary

_An alveary is a place where bees are kept, including a beehive or apiary enclosure._

The Alveary app is a native macOS AI agent orchestrator, written in Swift — like a hive of bees that works for you! It's built from scratch (with the help of agents), 
taking UX inspiration from other tools like [Codex](https://developers.openai.com/codex/app) and [Superset](https://superset.sh).

## Setup

Alveary is developed as a macOS app with Xcode 26.3, XcodeGen, `xcbeautify`, SwiftLint, and `knit-cli`.

Run the bootstrap script once per clone:

```sh
./scripts/setup.sh
```

That script installs the required CLI tools with Homebrew and Mint, including `xcbeautify` for prettified `xcodebuild` output, generates `Alveary.xcodeproj`, and configures the repo-local Git hooks so commits touching Swift files run `swiftlint` automatically.

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

The wrapper scripts use the same underlying build output path as the longer commands below.

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

`./scripts/snapshots.sh` defaults to `AlvearyTests/SnapshotTests` when no test identifier is provided.

## Project Config

Projects can define a local `.alveary.json` file in the repository root to control worktree setup behavior.

Example:

```json
{
  "scripts": {
    "setup": "bin/setup-worktree",
    "teardown": "bin/teardown-worktree"
  },
  "preservePatterns": [
    ".env",
    ".env.local",
    "config/*.json"
  ],
  "actions": []
}
```

`preservePatterns` is a list of glob patterns copied from the main project into each newly created worktree before the setup script runs. This is mainly for local-only files that should not come from Git, such as `.env` files or machine-specific config.

If `preservePatterns` is omitted, Alveary preserves `.env`, `.env.local`, and `.env.development` by default. If you provide `preservePatterns`, that list replaces the defaults.

Setup and teardown scripts run with `ALVEARY_THREAD_NAME`, `ALVEARY_BRANCH_NAME`, `ALVEARY_PROJECT_PATH`, `ALVEARY_WORKTREE_PATH`, and `ALVEARY_PORT_SEED` in their environment.

## Knit

Alveary uses `knit-cli gen` from the app target's Xcode pre-build script. That means builds already have a build hook for Knit, but the hook is CLI-based rather than `KnitBuildPlugin`-based. `project.yml` is the source of truth for that workflow, and the generated file remains `Alveary/DI/Generated/KnitExtensions.swift`.

# License

Alveary is licensed under the [GNU General Public License v3.0](LICENSE.md).
