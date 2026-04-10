## Keep AGENTS.md Up to Date

**WHEN** changes to dependencies, project structure, or lint rules are made, make sure `AGENTS.md` and `README.md` are kept up to date.
**WHEN** gotchas worth documenting are found, check if they belong in `AGENTS.md` to inform future sessions.

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

## Building, Testing, and Running

The project currently builds as the `Skep` scheme in `Skep.xcodeproj`. The app target's pre-build step requires `knit-cli`; install it with `mint install cashapp/knit knit-cli` if it is missing.

- First-time local setup: `./scripts/setup.sh` installs the required CLI tools, generates `Skep.xcodeproj`, and configures the repo-local Git hooks.
- Regenerate the Xcode project after project-structure changes with `xcodegen generate`.
- Build from the command line with `xcodebuild -project Skep.xcodeproj -scheme Skep -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode build`.
- Run the built app from the command line with `open .build/xcode/Build/Products/Debug/Skep.app`.
- Run the full test suite with `xcodebuild -project Skep.xcodeproj -scheme Skep -destination 'platform=macOS' -derivedDataPath .build/xcode test`.
- Run a focused test class with `xcodebuild -project Skep.xcodeproj -scheme Skep -destination 'platform=macOS' -derivedDataPath .build/xcode test -only-testing:SkepTests/AppDelegateTests`.
- For interactive development, you can also open `Skep.xcodeproj` in Xcode and run the `Skep` scheme directly.

## Linting

The project uses [SwiftLint](https://github.com/realm/SwiftLint) for code style and linting (`brew install swiftlint`).

- The repo ships a pre-commit hook at `.githooks/pre-commit` that runs `swiftlint` for commits touching Swift sources or `.swiftlint.yml`.
- Install the repo-managed hooks once with `./scripts/setup.sh` or `./scripts/install-git-hooks.sh`. This writes a repo-local `core.hooksPath=.githooks` override and does not modify your global Git hooks setup.
- The hook runs `swiftlint` from the project root so nested config discovery still works for `SkepTests/.swiftlint.yml`.
- Run `swiftlint` from the project root *without* `--config`; passing an explicit config file bypasses nested config discovery and breaks the `SkepTests/.swiftlint.yml` override.
- Run `swiftlint` manually when you want feedback before reaching the commit hook.

**WHEN** writing new Swift files, follow the rules in `.swiftlint.yml`. Key rules: no force unwraps outside of tests, no force casts, prefer `let` over `var`, max line length 150.

## General Code Style Guidelines

- Private types should always go *below* public types.
- Add concise code comments where needed for human readers.

## Repository Invariants

- `AgentRegistry` is the single source of truth for shared agent metadata. When adding or changing an agent, update `Skep/Services/Detection/DefaultAgentRegistry.swift` and derive provider install guidance, detection metadata, skills directories, and MCP integration metadata from that shared entry instead of introducing feature-local agent lists.
- `ClaudeConfigStore` is the sole serialized writer for Claude-owned config files (`~/.claude.json` and `.claude/settings.local.json`). Provider setup, trust-entry updates, and MCP config writes must continue to flow through it rather than performing direct read/merge/write cycles in feature services.
- `Project.remoteName` and `Project.gitRemote` are a paired invariant. Persist and update them together, and have Git/worktree/GitHub flows use the stored `remoteName` instead of rediscovering a remote ad hoc.
- `AgentsManager.destroyRuntime()` is the single public owner for destructive runtime teardown. Archive/delete/rollback flows should not reimplement `kill()` + wait loops + direct session-map removal on top of it.
- `SessionEntry`'s canonical cwd plus paired `appSessionId` / `launchSessionId` are required for Claude fork-session recovery and startup orphan cleanup. Resume/orphan flows must preserve both IDs and use canonicalized paths rather than recomputing ownership from raw process state alone.
- `SessionManager.persist()` must remain off `@MainActor`. `AppDelegate.applicationWillTerminate(_:)` bridges the final repair-path persist through `Task.detached` while synchronously blocking the main thread on a bounded semaphore; moving session persistence onto the main actor would deadlock shutdown.
- Worktree roots are namespaced by canonical project path under `../worktrees/`; preserve that namespacing so sibling clones with the same repo folder name cannot collide.
- The app layout uses a two-column `NavigationSplitView` with a conditional right-pane `HStack` detail split. Do not switch the diff pane back to native three-column `NavigationSplitViewVisibility` control on macOS 26; it does not behave correctly for programmatic right-pane toggling.

## macOS Lifecycle and Concurrency

- Keep `NSApplicationDelegate` implementations such as `AppDelegate` on `@MainActor`.
- When Swift 6 strict concurrency and AppKit interop fight each other in lifecycle code, prefer small explicit seams over broad workarounds: use injected dependencies for startup/shutdown behavior, and use `@preconcurrency import AppKit` only when needed to bridge AppKit/Objective-C sendability gaps.
- `.appWillTerminate` is an early shutdown contract, not a best-effort hint. Observers that own teardown required before process exit, such as file watchers or debounce tasks, must complete synchronously on the main actor rather than queueing follow-up cleanup behind `Task` hops.
- Shutdown paths that must complete before process exit should not rely on queued `Task { @MainActor ... }` cleanup. Prefer synchronous main-actor teardown for observer-driven lifecycle work that must happen before blocking termination waits.
