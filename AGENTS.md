## XCode Project Generation

The XCode project (`Skep.xcodeproj`) is generated from `project.yml` using XcodeGen (`brew install xcodegen`). **Never edit the `.xcodeproj` directly.**

**WHEN** you create a new `.swift` file, run `xcodegen generate` afterward so the file is included in the Xcode project. The glob-based `sources` in `project.yml` picks up files automatically from the folder structure, but the `.xcodeproj` must be regenerated to reflect the change.

**WHEN** you add a new SPM dependency, add it to the `packages` and `dependencies` sections of `project.yml`, then run `xcodegen generate`.

**WHEN** you add a new Knit `ModuleAssembly` file, place it in `Skep/DI/` (the path configured in `knitconfig.json`). Run `xcodegen generate` to pick up the new file.

**WHEN** you complete a planned phase or a substantial section inside one of the detailed `plan/part*.md` files, update the progress checkboxes in `PLAN.md` and the relevant detailed plan document before you finish. Future sessions should be able to resume from the repo docs alone.

**Knit/Xcode 26.3 note**: keep the Knit dependency pinned to revision `3d4afea562b95a95725f689be819b10ff93351fc` until a tagged release includes the upstream `KnitResolver` workaround for the `ExtractAppIntentsMetadata` crash.

**DO NOT** commit `Skep.xcodeproj/` — it is gitignored and regenerated from `project.yml`.

## Knit

The app uses `knit-cli gen` from the target pre-build script to generate `Skep/DI/Generated/KnitExtensions.swift`. Treat that file as generated output: keep it in the repo, but do not hand-edit it.

Add Knit `ModuleAssembly` files under `Skep/DI/`. If you add a new assembly or change resolver registrations in a way that should produce new generated resolver accessors, make sure the generated file is refreshed before you finish by building the app target or running the same `knit-cli gen` command used in `project.yml`.

Use the CLI-based Knit workflow documented in `project.yml`; do not switch the project over to `KnitBuildPlugin` unless the repo docs and build configuration are intentionally updated together.

## Linting

The project uses [SwiftLint](https://github.com/realm/SwiftLint) for code style and linting (`brew install swiftlint`).

**BEFORE** committing, run `swiftlint` from the project root to check for violations. Fix any errors before committing. Warnings are acceptable but should be minimized.

**WHEN** writing new Swift files, follow the rules in `.swiftlint.yml`. Key rules: no force unwraps outside of tests, no force casts, prefer `let` over `var`, max line length 150.

## General Code Style Guidelines

- Private types should always go *below* public types.
- Add concise code comments where needed for human readera.
