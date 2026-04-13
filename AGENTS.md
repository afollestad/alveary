## Keep AGENTS.md Up to Date

**WHEN** making changes, think about whether there are learnings that would be worth documenting for future agents in `AGENTS.md`.
**WHEN** making changes to dependencies, project structure, or lint, make sure `AGENTS.md` and `README.md` are kept up to date.

## XCode Project Generation

The XCode project (`Alveary.xcodeproj`) is generated from `project.yml` using XcodeGen (`brew install xcodegen`). **Never edit the `.xcodeproj` directly.**

**WHEN** you create a new `.swift` file, run `xcodegen generate` afterward so the file is included in the Xcode project. The glob-based `sources` in `project.yml` picks up files automatically from the folder structure, but the `.xcodeproj` must be regenerated to reflect the change.

**WHEN** you add a new SPM dependency, add it to the `packages` and `dependencies` sections of `project.yml`, then run `xcodegen generate`.

**WHEN** you add a new Knit `ModuleAssembly` file, place it in `Alveary/DI/` (the path configured in `knitconfig.json`). Run `xcodegen generate` to pick up the new file.

**Knit/Xcode 26.3 note**: keep the Knit dependency pinned to revision `3d4afea562b95a95725f689be819b10ff93351fc` until a tagged release includes the upstream `KnitResolver` workaround for the `ExtractAppIntentsMetadata` crash.

**DO NOT** commit `Alveary.xcodeproj/` — it is gitignored and regenerated from `project.yml`.

## Knit

The app uses `knit-cli gen` from the target pre-build script to generate `Alveary/DI/Generated/KnitExtensions.swift`. Treat that file as generated output: keep it in the repo, but do not hand-edit it.

Add Knit `ModuleAssembly` files under `Alveary/DI/`. If you add a new assembly or change resolver registrations in a way that should produce new generated resolver accessors, make sure the generated file is refreshed before you finish by building the app target or running the same `knit-cli gen` command used in `project.yml`.

Use the CLI-based Knit workflow documented in `project.yml`; do not switch the project over to `KnitBuildPlugin` unless the repo docs and build configuration are intentionally updated together.

## Building, Testing, and Running

The project currently builds as the `Alveary` scheme in `Alveary.xcodeproj`. The app target's pre-build step requires `knit-cli`; install it with `mint install cashapp/knit knit-cli` if it is missing.

- First-time local setup: `./scripts/setup.sh` installs the required CLI tools, including `xcbeautify` for prettified wrapper-script output, generates `Alveary.xcodeproj`, and configures the repo-local Git hooks.
- Regenerate the Xcode project after project-structure changes with `xcodegen generate`.
- Build from the command line with `./scripts/build.sh`.
- Run the full test suite with `./scripts/test.sh`.
- Run focused tests with `./scripts/test.sh AlvearyTests/AppDelegateTests` or multiple identifiers as separate arguments.
- See the "Snapshot Testing" section below for snapshot verification.
- Run the already-built app from the command line with `./scripts/run.sh`.
- The wrapper scripts use the same underlying commands as `xcodebuild -project Alveary.xcodeproj -scheme Alveary -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode build` and `open .build/xcode/Build/Products/Debug/Alveary.app`.
- For interactive development, you can also open `Alveary.xcodeproj` in Xcode and run the `Alveary` scheme directly.

## Snapshot Testing

- Use `./scripts/snapshots.sh` for snapshot workflows instead of prefixing `./scripts/test.sh` with `RECORD_SNAPSHOTS=1`; plain `xcodebuild test` does not reliably propagate that environment variable into the app-hosted macOS snapshot tests.
- Verify snapshot tests with `./scripts/snapshots.sh verify` and record them with `./scripts/snapshots.sh record`.
- `./scripts/snapshots.sh` defaults to `AlvearyTests/SnapshotTests`, and also accepts focused identifiers like `AlvearyTests/SnapshotTests/testSidebarViewPopulated`.
- Prefer focused companion snapshot files such as `SnapshotTests+Terminal.swift` instead of continuing to grow `SnapshotTests.swift`; keep snapshot coverage grouped by screen or feature area.
- Keep `assertMacSnapshot()` window-backed. macOS SwiftUI snapshots that render sidebar `List` content with custom section headers can capture as a blank background if they are hosted in a bare `NSHostingController` without an `NSWindow` display pass.
- Moving a snapshot test into a different file changes the baseline lookup path under `AlvearyTests/Snapshots/__Snapshots__/`; move or re-record the reference images to match the new companion file, and run `xcodegen generate` afterward if you added, removed, or renamed snapshot test source files.

Examples:
```sh
./scripts/snapshots.sh verify AlvearyTests/SnapshotTests/testSidebarViewPopulated
./scripts/snapshots.sh record AlvearyTests/SnapshotTests/testSidebarViewPopulated
```

Snapshots should be verified before committing, whenever UI is modified.

## Linting

The project uses [SwiftLint](https://github.com/realm/SwiftLint) for code style and linting (`brew install swiftlint`).

- The repo ships a pre-commit hook at `.githooks/pre-commit` that runs `swiftlint` for commits touching Swift sources or `.swiftlint.yml`.
- Install the repo-managed hooks once with `./scripts/setup.sh` or `./scripts/install-git-hooks.sh`. This writes a repo-local `core.hooksPath=.githooks` override and does not modify your global Git hooks setup.
- The hook runs `swiftlint` from the project root so nested config discovery still works for `AlvearyTests/.swiftlint.yml`.
- Run `swiftlint` from the project root *without* `--config`; passing an explicit config file bypasses nested config discovery and breaks the `AlvearyTests/.swiftlint.yml` override.
- Run `swiftlint` manually when you want feedback before reaching the commit hook.
- *If a change introduces new lint warnings and/or errors, inform the user before following through with a commit.*

**WHEN** writing new Swift files, follow the rules in `.swiftlint.yml`. Key rules: no force unwraps outside of tests, no force casts, prefer `let` over `var`, max line length 150.

## General Guidelines

- Private types should always go *below* public types.
- Add concise code comments where needed for human readers.
- When updating non-UI logic, check if unit tests need to be updated and/or if new cases need to be added.
- When updating UI, check if snapshot tests need to be updated and/or if new cases need to be added.
- Large types may be split into companion files like `Type+Feature.swift`. When reading current behavior or adding new logic to an existing type, search for same-type extensions and treat those companion files as part of the canonical implementation before editing.
- Prefer categorized companion files once a type starts accumulating distinct concerns, such as `TerminalPane+ResizeHandle.swift` or `TerminalPane+SessionViews.swift`, instead of continuing to grow a single base file.
- In SwiftUI, prefer extracted `View` types over `some View` extension properties. Keep trivial one-off stacks inline, and only extract when it clarifies composition. When an extracted child view is used by another view, place it in the same folder with `Parent+Child.swift` naming such as `DiffViewerPane+Header.swift`.
- For SwiftUI buttons, use the shared `primaryActionButtonStyle()`, `secondaryActionButtonStyle()`, and `destructiveActionButtonStyle()` modifiers from `Alveary/Views/Components/ActionControls.swift`. Reserve `.plain` and `.borderless` for low-emphasis affordances.

## Repository Invariants

- `AgentRegistry` is the single source of truth for shared agent metadata. When adding or changing an agent, update `Alveary/Services/Detection/DefaultAgentRegistry.swift` and derive provider install guidance, detection metadata, skills directories, and MCP integration metadata from that shared entry instead of introducing feature-local agent lists.
- `ClaudeConfigStore` is the sole serialized writer for Claude-owned config in `~/.claude.json`. Provider setup, trust-entry updates, and MCP config writes must continue to flow through it rather than performing direct read/merge/write cycles in feature services.
- Project actions are edited from project settings via `.alveary.json`, but they surface in the main toolbar only while a thread for that project is selected. Execution should prefer the thread's `worktreePath` and only fall back to the project root when no worktree exists.
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

## Provider and Tooling Gotchas

- Claude structured streaming requires `--verbose` alongside `--output-format stream-json`; dropping `--verbose` produces no structured output.
- Do not re-add Claude `--include-hook-events` in `-p` mode; it does not emit useful hook events there, and lifecycle state should continue to derive from the standard event stream and process lifecycle.
- Claude resume checks must use the canonical cwd. If the expected `~/.claude/projects/<encoded-cwd>/<session>.jsonl` file is missing, `--resume <id>` fails immediately; only then should the adapter fall back to `--session-id <same-id>` to recreate a fresh session file.
- `gh auth login --web` does not auto-open the browser without a TTY. GitHub auth flows in the app must continue parsing the emitted URL/code and opening the browser explicitly.
- Claude auto-denies `AskUserQuestion` in `-p --output-format stream-json` mode. Keep the app-native prompt/selection UI as the interaction path instead of expecting the CLI to pause for an answer.
