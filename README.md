# Skep

_A skep is a traditional beehive made from coiled straw or wicker, historically used to house honey bees._

The Skep app is a native macOS AI agent orchestrator, written in Swift — like a hive of bees that works for you! It's built from scratch (with the help of agents), 
taking UX inspiration from other tools like [Codex](https://developers.openai.com/codex/app) and [Superset](https://superset.sh).

## Setup

Skep is developed as a macOS app with Xcode 26.3, XcodeGen, SwiftLint, and `knit-cli`.

Run the bootstrap script once per clone:

```sh
./scripts/setup.sh
```

That script installs the required CLI tools with Homebrew and Mint, generates `Skep.xcodeproj`, and configures the repo-local Git hooks so commits touching Swift files run `swiftlint` automatically.

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
./scripts/test.sh SkepTests/AppDelegateTests
```

## Snapshot Tests

Verify the full snapshot suite:

```sh
./scripts/snapshots.sh verify
```

Verify or record a focused snapshot test:

```sh
./scripts/snapshots.sh verify SkepTests/SnapshotTests/testSidebarViewPopulated
./scripts/snapshots.sh record SkepTests/SnapshotTests/testSidebarViewPopulated
```

`./scripts/snapshots.sh` defaults to `SkepTests/SnapshotTests` when no test identifier is provided.

## Knit

Skep uses `knit-cli gen` from the app target's Xcode pre-build script. That means builds already have a build hook for Knit, but the hook is CLI-based rather than `KnitBuildPlugin`-based. `project.yml` is the source of truth for that workflow, and the generated file remains `Skep/DI/Generated/KnitExtensions.swift`.
