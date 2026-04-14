# Alveary

_An alveary is a place where bees are kept, including a beehive or apiary enclosure._

This app is an agent orchestration tool for macOS, like a swarm of bees working towards a common goal. 
It's built from the ground up in native Swift, with the help of agents! I took inspiration from other tools like Conductor and Codex.

See the backlog/roadmap [here](https://github.com/users/afollestad/projects/3)!

# Development

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

# License

Alveary is licensed under the [GNU General Public License v3.0](LICENSE.md).
