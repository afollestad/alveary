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
xcodebuild -project Skep.xcodeproj -scheme Skep -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode build
```

Run the app:

```sh
open .build/xcode/Build/Products/Debug/Skep.app
```

Run the full test suite:

```sh
xcodebuild -project Skep.xcodeproj -scheme Skep -destination 'platform=macOS' -derivedDataPath .build/xcode test
```

Run a focused test class:

```sh
xcodebuild -project Skep.xcodeproj -scheme Skep -destination 'platform=macOS' -derivedDataPath .build/xcode test -only-testing:SkepTests/AppDelegateTests
```

## Knit

Skep uses `knit-cli gen` from the app target's Xcode pre-build script. That means builds already have a build hook for Knit, but the hook is CLI-based rather than `KnitBuildPlugin`-based. `project.yml` is the source of truth for that workflow, and the generated file remains `Skep/DI/Generated/KnitExtensions.swift`.

# License

Alveary is licensed under the [GNU General Public License v3.0](LICENSE.md).
