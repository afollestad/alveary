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

- When updating non-UI logic, check if unit tests need to be updated and/or if new cases need to be added.
- When updating UI, check if snapshot tests need to be updated and/or if new cases need to be added.
- Use `./scripts/snapshots.sh` for snapshot workflows instead of prefixing `./scripts/test.sh` with `RECORD_SNAPSHOTS=1`; plain `xcodebuild test` does not reliably propagate that environment variable into the app-hosted macOS snapshot tests.
- Verify snapshot tests with `./scripts/snapshots.sh verify` and record them with `./scripts/snapshots.sh record`.
- `./scripts/snapshots.sh record` is expected to exit non-zero after writing updated baselines because SnapshotTesting reports recorded snapshots as test failures in record mode; treat a follow-up `./scripts/snapshots.sh verify ...` pass as the confirmation step.
- `./scripts/snapshots.sh` defaults to `AlvearyTests/SnapshotTests`, and also accepts focused identifiers like `AlvearyTests/SnapshotTests/testSidebarViewPopulated`.
- Prefer focused companion snapshot files such as `SnapshotTests+Terminal.swift` instead of continuing to grow `SnapshotTests.swift`; keep snapshot coverage grouped by screen or feature area.
- Keep `assertMacSnapshot()` window-backed. macOS SwiftUI snapshots that render sidebar `List` content with custom section headers can capture as a blank background if they are hosted in a bare `NSHostingController` without an `NSWindow` display pass.
- `assertMacSnapshot()` supports dark-mode coverage via its `colorScheme:` argument; when adding dark-mode snapshots, keep the SwiftUI `colorScheme` and the hosting `NSAppearance` in sync or AppKit-backed colors such as `separatorColor` will render incorrectly.
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

## Code Style And File Organization

These are default structure and readability conventions for new code and routine edits. Follow them unless a nearby type already has an established local pattern.

- Private types should always go *below* public types.
- Add concise code comments where needed for human readers.
- Large types may be split into companion files like `Type+Feature.swift`. When reading current behavior or adding new logic to an existing type, search for same-type extensions and treat those companion files as part of the canonical implementation before editing.
- Prefer categorized companion files once a type starts accumulating distinct concerns, such as `TerminalPane+ResizeHandle.swift` or `TerminalPane+SessionViews.swift`, instead of continuing to grow a single base file. Also lean on companion files earlier to avoid files becoming too large, and use them to resolve lint warnings about file length.
- In SwiftUI, prefer extracted `View` types over `some View` extension properties. Keep trivial one-off stacks inline, and only extract when it clarifies composition. When an extracted child view is used by another view, place it in the same folder with `Parent+Child.swift` naming such as `DiffViewerPane+Header.swift`.

## Interaction Contracts

These capture repo-specific interaction patterns and UI implementation choices. Keep new UI aligned with them unless you are intentionally redesigning the behavior across the app.

- Thread rename is inline (Finder-style `TextField` swap in `SidebarThreadRow`), not a modal sheet. The row tracks an `editingThreadID` binding. Conversation rename in multi-conversation tabs uses the same inline pattern via `editingConversationID` in `ConversationTabChip`.
- Session reconfiguration is a between-turn action. Do not let agent/session setting changes reconfigure a conversation while a turn is active or a send is still in flight; those changes must wait until the current turn finishes.
- For SwiftUI buttons, use the shared `primaryActionButtonStyle()`, `secondaryActionButtonStyle()`, and `destructiveActionButtonStyle()` modifiers from `Alveary/Views/Components/ActionControls.swift`. Reserve `.plain` and `.borderless` for low-emphasis affordances.
- For icon-bearing action buttons that use the shared prominent button styles, prefer explicit `Image` + `Text` content over `Label`; on macOS the shared style can render `Label` as text-only in some contexts.
- Queued messages stay stacked above the chat composer until they are actually sent. Do not render pending queued entries in the transcript as if they were already part of the conversation history.
- Once a queued message is actually attempted, it belongs to the transcript. If that attempted send fails, show retry affordances on the transcript user message rather than moving it back into the queued-message list.
- While a turn is active, keep transcript updates incremental. Persisted live-turn events should append directly into `ChatItemGrouper`, and full transcript regrouping from the `events` query should be deferred until the turn ends so the active turn does not starve composer interactions like autocomplete or text insertion.
- Live root-assistant `messageChunk` events should be coalesced before they hop onto the main actor. Do not process every streamed text delta as its own `MainActor` mutation, or active turns can starve transcript completion and composer interactions.
- Transcript auto-follow should stay pinned when the user is already at the bottom and new content increases transcript height, including wrapped streaming-bubble growth. Treat content-size growth differently from a user-initiated scroll-away so the `Jump to bottom` affordance only appears after the user actually leaves the bottom.
- In `ChatTranscriptView`, keep the bottom inset inside the `chat-bottom` scroll target instead of as trailing stack padding. Bottom padding after the anchor leaves a small extra scroll range when entering a thread or jumping to the bottom.
- Transcript follow mode should also survive transcript viewport-height changes caused by bottom-area composer banners or strips appearing and disappearing. If the user did not scroll and they were already near bottom, treat container-height changes like other bottom-pinned layout changes and keep the transcript anchored.
- `ConversationViewModel` agent subscriptions are view-lifecycle owned, not initializer-owned. Keep `activateViewLifecycle()` / `deactivateViewLifecycle()` wired from `ConversationView`'s `.task` and `.onDisappear` instead of restarting subscriptions from `init`, because parent SwiftUI refreshes can recreate the model and churn `activeSubscriptionToken`.
- The macOS chat composer uses the AppKit-backed `AppTextEditor`/`AppKitTextView` bridge. Keep the placeholder drawn inside `AppKitTextView` instead of reintroducing a SwiftUI overlay so it shares the real `NSTextView` insets and caret positioning.
- `TextSelection` values flowing through the AppKit editor can briefly refer to an older string right after send/reset updates. Any code that maps those indices into the current string, including `NSTextView` sync and autocomplete/mention helpers, must treat stale indices as invalid and normalize or bail out instead of assuming the indices still belong to the new text. Keep selection/replacement offsets in UTF-16 units to match AppKit `NSRange` behavior; mixing them with `String.count` breaks emoji/composed-character handling.
- Composer token styling in `AppKitTextView` should be applied as attributed ranges while keeping the editor's base `textColor`/typing color pinned to the normal label color. Deriving the base color from already-styled text can cause accent-colored mentions or slash commands to bleed into later plain text or persist after clearing the input.
- Slash-command argument hints are visual-only `AppKitTextView` inline hints driven by skill frontmatter (`argument-hint`). Keep them out of the underlying composer `text` and hide them once the user starts typing real arguments or moves the caret away from the end of the command.
- Composer autocomplete source loading and filtering must not inherit the live-turn `MainActor` workload. Run the expensive work off-main and only hop back to publish `activeAutocomplete` state so `@` mentions and `/` skills stay responsive while a turn is streaming.
- Composer autocomplete is anchored to the top edge of the editor itself, not above the entire composer stack. Keep the popup as an overlay on `AppTextEditor` so it floats over queued-message rows and changed-files strips, while file suggestions show canonical display paths and skill suggestions stay in the single-line icon/name/description/scope layout.
- Composer autocomplete loading and empty placeholder states should share the same full-width popup container and surface color as populated suggestions; keep focused snapshots for files, skills, empty, and loading variants when changing popup styling.
- For selectable list rows (sidebar items, settings tabs, diff file lists), use the `.appSelectableRow(isSelected:action:)` modifier from `Alveary/Views/Components/SelectionRowBackground.swift`. It bundles `contentShape`, tap gesture, press-highlight feedback, accessibility selection traits, and `listRowBackground` into a single call. Do not use `Button` with `.plain` style for list rows — `Button` does not reliably fill the full row hit area in a `List`.
- Conversation tab chips are not list rows, but they should mirror the same press-feedback principles: let the select action own the full capsule hit area, overlay trailing affordances like the close button on top of that surface, and prefer fill changes over capsule strokes for selected styling because macOS can render stray vertical artifacts from chip outlines in snapshots.
- Sidebar keyboard navigation traverses items in a flat order: Skills → MCP → each project row (with its active threads interleaved when the project is expanded) → next project. The traversal is built by `buildNavigableItems()` and driven by `navigateVertically()` in `SidebarView+KeyboardNavigation.swift`. Horizontal arrows intentionally reuse that vertical path in some cases: left-arrow behaves like up-arrow for `Skills`, `MCP`, thread rows, and already-collapsed project rows, while right-arrow behaves like down-arrow for `Skills`, `MCP`, thread rows, and already-expanded project rows; collapsed/expanded project rows still use left/right to collapse/expand first. When adding new top-level sidebar sections or changing expansion behavior, update these functions and their tests.
- `ThreadDetailConversationTabs` should keep the system `.bar` background for the header chrome and add any custom separator as an overlay. Replacing the bar with `windowBackgroundColor` creates an unintended dark strip in the live app.

## Repository Invariants

These are architectural and persistence contracts. Treat them as hard constraints unless the work explicitly includes a coordinated migration.

- `AgentRegistry` is the single source of truth for shared agent metadata. When adding or changing an agent, update `Alveary/Services/Detection/DefaultAgentRegistry.swift` and derive provider install guidance, detection metadata, skills directories, and MCP integration metadata from that shared entry instead of introducing feature-local agent lists.
- `AgentThread.name` stores the visible thread label, while `AgentThread.hasCustomName` distinguishes a manual rename from the default untitled state. Manual thread rename flows must set `hasCustomName`, and thread auto-naming should only fire while the thread is still effectively untitled (`!hasCustomName && trimmedName == "New thread"`). Conversation auto-titling is a separate rule: the first user message may set `Conversation.title` whenever `customTitle == nil`, even if the thread already has a non-default name. Thread rename cascades to the main conversation's `title` when it still has its default name (`customTitle == nil`); do not add a separate rename affordance for the sole conversation when only one exists.
- Archived-thread restore uses persisted per-conversation `pendingRestoreContext`, not provider resume. Restoring a thread should regenerate that summary from saved `ConversationEventRecord`s, hydrate it back into `ConversationState.stagedContext` when the conversation view model is recreated, send it only through the existing staged-context path on the next outbound message, and clear the persisted field when the user dismisses it or that send succeeds.
- `DataAssembly` owns the on-disk SwiftData location. Keep the app store scoped under `~/Library/Application Support/Alveary/Alveary.store` so local resets stay app-specific and never fall back to the generic `default.store` path.
- `ClaudeConfigStore` is the sole serialized writer for Claude-owned config in `~/.claude.json`. Provider setup, trust-entry updates, and MCP config writes must continue to flow through it rather than performing direct read/merge/write cycles in feature services.
- `.alveary.json` writes are a selective round-trip, not a wholesale rewrite. The project settings editor only owns `scripts.setup`, `scripts.teardown`, `preservePatterns`, and `actions`; when saving supported config, preserve non-editable supported fields such as `scripts.setupTimeoutSeconds` and `shellSetup` instead of dropping them.
- Project actions are edited from project settings via `.alveary.json`, but they surface in the main toolbar only while a thread for that project is selected. Execution should prefer the thread's `worktreePath` and only fall back to the project root when no worktree exists.
- `Project.remoteName` and `Project.gitRemote` are a paired invariant. Persist and update them together, and have Git/worktree/GitHub flows use the stored `remoteName` instead of rediscovering a remote ad hoc.
- `AgentsManager.destroyRuntime()` is the single public owner for destructive runtime teardown. Archive/delete/rollback flows should not reimplement `kill()` + wait loops + direct session-map removal on top of it.
- `SessionEntry`'s canonical cwd plus paired `appSessionId` / `launchSessionId` are required for Claude fork-session recovery and startup orphan cleanup. Resume/orphan flows must preserve both IDs and use canonicalized paths rather than recomputing ownership from raw process state alone.
- `SessionManager.persist()` must remain off `@MainActor`. `AppDelegate.applicationWillTerminate(_:)` bridges the final repair-path persist through `Task.detached` while synchronously blocking the main thread on a bounded semaphore; moving session persistence onto the main actor would deadlock shutdown.
- Worktree roots are namespaced by canonical project path under `../worktrees/`; preserve that namespacing so sibling clones with the same repo folder name cannot collide.
- Worktree lifecycle scripts from `.alveary.json` have stable defaults and rollback behavior. `scripts.setup` runs in the new worktree with a default 300-second timeout unless `scripts.setupTimeoutSeconds` overrides it; `scripts.teardown` runs during removal with a 60-second timeout; both receive `ALVEARY_THREAD_NAME`, `ALVEARY_PROJECT_PATH`, `ALVEARY_WORKTREE_PATH`, optional `ALVEARY_BRANCH_NAME`, and `ALVEARY_PORT_SEED`. If `scripts.setup` fails, the manager must attempt to remove the new worktree and delete the rollback branch before surfacing the error.
- Preserved-file copying during worktree creation defaults to `.env`, `.env.local`, and `.env.development` when `.alveary.json` omits `preservePatterns`. Custom `preservePatterns` replace that default list.
- The app layout uses a two-column `NavigationSplitView` with a conditional right-pane `HStack` detail split. Do not switch the diff pane back to native three-column `NavigationSplitViewVisibility` control on macOS 26; it does not behave correctly for programmatic right-pane toggling.

## macOS Lifecycle and Concurrency

- Keep `NSApplicationDelegate` implementations such as `AppDelegate` on `@MainActor`.
- When Swift 6 strict concurrency and AppKit interop fight each other in lifecycle code, prefer small explicit seams over broad workarounds: use injected dependencies for startup/shutdown behavior, and use `@preconcurrency import AppKit` only when needed to bridge AppKit/Objective-C sendability gaps.
- `.appWillTerminate` is an early shutdown contract, not a best-effort hint. Observers that own teardown required before process exit, such as file watchers or debounce tasks, must complete synchronously on the main actor rather than queueing follow-up cleanup behind `Task` hops.
- Shutdown paths that must complete before process exit should not rely on queued `Task { @MainActor ... }` cleanup. Prefer synchronous main-actor teardown for observer-driven lifecycle work that must happen before blocking termination waits.

## Provider and Tooling Gotchas

- Claude structured streaming requires `--verbose` alongside `--output-format stream-json`; dropping `--verbose` produces no structured output.
- Do not re-add Claude `--include-hook-events` in `-p` mode; it does not emit useful hook events there, and lifecycle state should continue to derive from the standard event stream and process lifecycle.
- Do not switch `DefaultAgentsManager.readAgentOutput` back to `FileHandle.AsyncBytes.lines` for Claude's stream-json pipe. Keep the `readabilityHandler`-based `PipeLinePump` so final EOF-delimited JSON records without a trailing newline still flush and the UI does not get stuck in a busy/Stop state.
- Claude resume checks must use the canonical cwd. If the expected `~/.claude/projects/<encoded-cwd>/<session>.jsonl` file is missing, `--resume <id>` fails immediately; only then should the adapter fall back to `--session-id <same-id>` to recreate a fresh session file.
- `gh auth login --web` does not auto-open the browser without a TTY. GitHub auth flows in the app must continue parsing the emitted URL/code and opening the browser explicitly.
- Claude auto-denies `AskUserQuestion` in `-p --output-format stream-json` mode. Keep the app-native prompt/selection UI as the interaction path instead of expecting the CLI to pause for an answer.
