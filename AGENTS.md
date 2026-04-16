## Keep AGENTS.md Up to Date

**WHEN** making changes, think about whether there are learnings that would be worth documenting for future agents in `AGENTS.md`.
**WHEN** making changes to dependencies, project structure, or lint, make sure `AGENTS.md` and `README.md` are kept up to date.
**WHEN** adding or updating agent guidance, prefer the narrowest `AGENTS.md` whose scope covers the affected files. Keep instructions in the root `AGENTS.md` only when they are truly repo-wide or protect cross-cutting invariants.

## Scoped AGENTS Files

Use nested `AGENTS.md` files to keep local guidance close to the code it governs.

- `Alveary/DI/AGENTS.md` covers Knit assemblies and generated DI output.
- `Alveary/Services/Git/AGENTS.md` covers worktree lifecycle and the GitHub CLI adapter.
- `Alveary/Views/AGENTS.md` covers shared SwiftUI view composition rules.
- `Alveary/Views/Components/AGENTS.md` covers shared component and `AppTextEditor` implementation details.
- `Alveary/Views/Chat/AGENTS.md` covers chat-specific view chrome and tab behavior.
- `Alveary/Views/Input/AGENTS.md` covers composer autocomplete, slash-command hints, and worktree picker behavior.
- `Alveary/Views/Sidebar/AGENTS.md` covers sidebar-specific interaction patterns.
- `AlvearyTests/AGENTS.md` covers snapshot and test-organization guidance.

**WHEN** creating a new nested `AGENTS.md`, also add a sibling `CLAUDE.md` symlink to it (`ln -s AGENTS.md CLAUDE.md` from inside that directory) so Claude Code picks up the scoped guidance, and add a line for the new file to the list above. The root `project.yml` already excludes `**/CLAUDE.md` from Xcode sources, so no project regeneration is required.

## XCode Project Generation

The XCode project (`Alveary.xcodeproj`) is generated from `project.yml` using XcodeGen (`brew install xcodegen`). **Never edit the `.xcodeproj` directly.**

**WHEN** you create a new `.swift` file, run `xcodegen generate` afterward so the file is included in the Xcode project. The glob-based `sources` in `project.yml` picks up files automatically from the folder structure, but the `.xcodeproj` must be regenerated to reflect the change.

**WHEN** you add a new SPM dependency, add it to the `packages` and `dependencies` sections of `project.yml`, then run `xcodegen generate`.

**WHEN** you add a new Knit `ModuleAssembly` file, place it in `Alveary/DI/` (the path configured in `knitconfig.json`). Run `xcodegen generate` to pick up the new file.

**Knit/Xcode 26.3 note**: keep the Knit dependency pinned to revision `3d4afea562b95a95725f689be819b10ff93351fc` until a tagged release includes the upstream `KnitResolver` workaround for the `ExtractAppIntentsMetadata` crash.

**DO NOT** commit `Alveary.xcodeproj/` — it is gitignored and regenerated from `project.yml`.

## Building, Testing, and Running

The project currently builds as the `Alveary` scheme in `Alveary.xcodeproj`. The app target's pre-build step requires `knit-cli`; install it with `mint install cashapp/knit knit-cli` if it is missing.

- First-time local setup: `./scripts/setup.sh` installs the required CLI tools, including `xcbeautify` for prettified wrapper-script output, generates `Alveary.xcodeproj`, and configures the repo-local Git hooks.
- Regenerate the Xcode project after project-structure changes with `xcodegen generate`.
- Build from the command line with `./scripts/build.sh`.
- Run the full test suite with `./scripts/test.sh`.
- Run focused tests with `./scripts/test.sh AlvearyTests/AppDelegateTests` or multiple identifiers as separate arguments.
- See `AlvearyTests/AGENTS.md` for snapshot verification details.
- Run the already-built app from the command line with `./scripts/run.sh`.
- The wrapper scripts use the same underlying commands as `xcodebuild -project Alveary.xcodeproj -scheme Alveary -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode build` and `open .build/xcode/Build/Products/Debug/Alveary.app`.
- For interactive development, you can also open `Alveary.xcodeproj` in Xcode and run the `Alveary` scheme directly.
- When actively working on something, if the user needs to manually test, run `./scripts/build.sh` first and wait for it to exit successfully before running `./scripts/run.sh`.
- Never run `./scripts/build.sh` and `./scripts/run.sh` in parallel, and do not start `./scripts/run.sh` until the build has completed.
- Do not use `multi_tool_use.parallel` for any ordered validation workflow such as build-then-run, build-then-test, or record-then-verify snapshots. If one command depends on the previous command's result, run them strictly serially.
- If the user asks to build and then run after each iteration, treat that as a hard sequencing requirement: finish `./scripts/build.sh`, confirm success, and only then start `./scripts/run.sh`.

- When updating non-UI logic, check if unit tests need to be updated and/or if new cases need to be added.
- When updating UI, check if snapshot tests need to be updated and/or if new cases need to be added.
- Use `./scripts/snapshots.sh` for snapshot workflows, and verify snapshots before committing whenever UI is modified. See `AlvearyTests/AGENTS.md` for the focused snapshot-specific rules.

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

## Interaction Contracts

These capture repo-specific interaction patterns and UI implementation choices. Keep new UI aligned with them unless you are intentionally redesigning the behavior across the app.

- Session reconfiguration is a between-turn action. Do not let agent/session setting changes reconfigure a conversation while a turn is active or a send is still in flight; those changes must wait until the current turn finishes.
- Queued messages stay stacked above the chat composer until they are actually sent. Do not render pending queued entries in the transcript as if they were already part of the conversation history.
- Once a queued message is actually attempted, it belongs to the transcript. If that attempted send fails, show retry affordances on the transcript user message rather than moving it back into the queued-message list.
- User-requested turn cancellation is an interruption, not a generic failure. Stopped turns should clear composer error banners, render a centered `Interrupted` transcript note, and persist a `stop` session note so restore/archive context does not summarize the turn as an error.
- User-requested cancellation of initial-setup (worktree creation + agent spawn for a new thread) is a reset, not a failure. `ConversationViewModel.cancel()` must cancel the tracked `initialSetupTask` and flip `state.isCancellingInitialSetup = true` so the composer shows a spinner instead of the stop button; the existing `rollbackFailedInitialSetup` path restores the draft and clears `hasCompletedInitialSetup`, and `sendDraft` / `retryDraft` must swallow `CancellationError` so no error banner appears. A subsequent send re-enters setup via the normal `needsSetup` check.
- While a turn is active, keep transcript updates incremental. Persisted live-turn events should append directly into `ChatItemGrouper`, and full transcript regrouping from the `events` query should be deferred until the turn ends so the active turn does not starve composer interactions like autocomplete or text insertion.
- Live root-assistant `messageChunk` events should be coalesced before they hop onto the main actor. Do not process every streamed text delta as its own `MainActor` mutation, or active turns can starve transcript completion and composer interactions.
- `ConversationViewModel` agent subscriptions are view-lifecycle owned, not initializer-owned. Keep `activateViewLifecycle()` / `deactivateViewLifecycle()` wired from `ConversationView`'s `.task` and `.onDisappear` instead of restarting subscriptions from `init`, because parent SwiftUI refreshes can recreate the model and churn `activeSubscriptionToken`.

## Repository Invariants

These are architectural and persistence contracts. Treat them as hard constraints unless the work explicitly includes a coordinated migration.

- `AgentRegistry` is the single source of truth for shared agent metadata. When adding or changing an agent, update `Alveary/Services/Detection/DefaultAgentRegistry.swift` and derive provider install guidance, detection metadata, skills directories, and MCP integration metadata from that shared entry instead of introducing feature-local agent lists.
- `AgentThread.name` stores the visible thread label, while `AgentThread.hasCustomName` distinguishes a manual rename from the default untitled state. Manual thread rename flows must set `hasCustomName`, and thread auto-naming should only fire while the thread is still effectively untitled (`!hasCustomName && trimmedName == "New thread"`). Conversation auto-titling is a separate rule: the first user message may set `Conversation.title` whenever `customTitle == nil`, even if the thread already has a non-default name. Thread rename cascades to the main conversation's `title` when it still has its default name (`customTitle == nil`); do not add a separate rename affordance for the sole conversation when only one exists.
- Archived-thread restore uses persisted per-conversation `pendingRestoreContext`, not provider resume. Restoring a thread should regenerate that summary from saved `ConversationEventRecord`s, hydrate it back into `ConversationState.stagedContext` when the conversation view model is recreated, send it only through the existing staged-context path on the next outbound message, and clear the persisted field when the user dismisses it or that send succeeds.
- Launch-time "re-open last thread and conversation" restore is exact-match and best-effort. Only restore when both persisted `lastOpenThreadID` and `lastOpenConversationID` still resolve to the same live, unarchived thread/conversation pair; otherwise clear the saved IDs and fall back to the normal empty selection state.
- `DataAssembly` owns the on-disk SwiftData location. Keep the app store scoped under `~/Library/Application Support/Alveary/Alveary.store` so local resets stay app-specific and never fall back to the generic `default.store` path.
- `ClaudeConfigStore` is the sole serialized writer for Claude-owned config in `~/.claude.json`. Provider setup, trust-entry updates, and MCP config writes must continue to flow through it rather than performing direct read/merge/write cycles in feature services.
- `.alveary.json` writes are a selective round-trip, not a wholesale rewrite. The project settings editor only owns `scripts.setup`, `scripts.teardown`, `preservePatterns`, and `actions`; when saving supported config, preserve non-editable supported fields such as `scripts.setupTimeoutSeconds` and `shellSetup` instead of dropping them. If the merged supported config normalizes to no meaningful values, delete `.alveary.json` instead of persisting an empty `{}` file.
- Project actions are edited from project settings via `.alveary.json`, but they surface in the main toolbar only while a thread for that project is selected. Execution should prefer the thread's `worktreePath` and only fall back to the project root when no worktree exists.
- `Project.remoteName` and `Project.gitRemote` are a paired invariant. Persist and update them together, and have Git/worktree/GitHub flows use the stored `remoteName` instead of rediscovering a remote ad hoc.
- `AgentsManager.destroyRuntime()` is the single public owner for destructive runtime teardown. Archive/delete/rollback flows should not reimplement `kill()` + wait loops + direct session-map removal on top of it.
- `SessionEntry`'s canonical cwd plus paired `appSessionId` / `launchSessionId` are required for Claude fork-session recovery and startup orphan cleanup. Resume/orphan flows must preserve both IDs and use canonicalized paths rather than recomputing ownership from raw process state alone.
- `SessionManager.persist()` must remain off `@MainActor`. `AppDelegate.applicationWillTerminate(_:)` bridges the final repair-path persist through `Task.detached` while synchronously blocking the main thread on a bounded semaphore; moving session persistence onto the main actor would deadlock shutdown.
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
- Claude auto-denies `AskUserQuestion` in `-p --output-format stream-json` mode. Keep the app-native prompt/selection UI as the interaction path instead of expecting the CLI to pause for an answer.
