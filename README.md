# Alveary

_An alveary is a place where bees are kept, including a beehive or apiary enclosure._

Alveary is a native macOS app for orchestrating AI coding agents in parallel. Inspired by Conductor and Codex, and built in Swift with help from the agents themselves.

See the backlog/roadmap [here](https://github.com/users/afollestad/projects/3)!

# Development

## Setup

Alveary is built with XcodeGen, `xcbeautify`, SwiftLint, and `knit-cli`.

Run the bootstrap script once per clone:

```sh
./scripts/setup.sh
```

It installs the required CLI tools via Homebrew and Mint (including `xcbeautify` for prettified `xcodebuild` output), generates `Alveary.xcodeproj`, and configures the repo-local Git hooks so commits touching Swift files run `swiftlint` automatically.

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

# License

Alveary is licensed under the [GNU General Public License v3.0](LICENSE.md).
