# Skep App Research

Reference architecture for an app that interfaces with AI coding agents. Initial version supports Claude Code only; the architecture is modular so additional agents (Codex, Amp, Goose, etc.) can be added later. Covers the full pipeline from spawning an agent to displaying its output, and all the supporting systems around session management, hooks, permissions, and more.

---

# Implementation Guide

This document is organized in four Parts, each building on the previous. **The Phase tables below define the build order** — follow them sequentially. Parts 1 and most of Part 3 can be read top to bottom. Part 2 and the Phase 6 UI work intentionally use the phase tables as the source of truth for build order, because some shared runtime/UI components are documented in later files than the views that consume them.

Each Part is split across multiple files for readability:

**Part 1: Foundation**
- [Part 1a: Setup](plan/part1a-setup.md) — Xcode project generation, SPM dependencies, library stack, project structure, Knit DI.
- [Part 1b: Data and Services](plan/part1b-data-and-services.md) — App database, state management, settings, concurrency, shell runner, service layer table.
- [Part 1c: Settings UI](plan/part1c-settings-ui.md) — Settings screen layout, SettingsViewModel, how each setting is applied.
- [Part 1d: Diff Parser](plan/part1d-diff-parser.md) — DiffFile, DiffHunk, DiffLine, DiffParser. Pure parsing utility, no dependencies.
- [Part 1e: Events and Notifications](plan/part1e-events.md) — Universal event model, config types, error types, NotificationManager.

**Part 2: Agent Integration**
- [Part 2a: Providers](plan/part2a-providers.md) — Provider adapters, registry, detection, environment, turn state/message queue, activity classification.
- [Part 2b: Event Grouping](plan/part2b-event-grouping.md) — ChatItem, ToolEntry, SubAgentEntry, TaskEntry, ChatItemGrouper.
- [Part 2c: Agent Process Management](plan/part2c-agents-manager.md) — AgentsManager, ConversationState, streaming pipeline.
- [Part 2d: EventBuffer and Agent Lifecycle](plan/part2d-spawn-and-buffer.md) — EventBuffer, spawn, subscribe, and replay bookkeeping.
- [Supplement: Agent Runtime Teardown and Reconfiguration](plan/supplement-agent-runtime-teardown.md) — `sendMessage`, kill/reconfigure flows, teardown, and exit cleanup.
- [Part 2e: Turn Lifecycle and ClaudeAdapter](plan/part2e-turn-and-adapter.md) — Turn state lifecycle, event JSON schemas, sub-agent event flow, ClaudeAdapter.
- [Part 2f: ViewModel](plan/part2f-viewmodel.md) — `ConversationViewModel` lifecycle, persistence, and event routing.
- [Supplement: ConversationViewModel Behaviors](plan/supplement-conversation-viewmodel-behaviors.md) — `SetupPhase`, auto-naming, staged context, and queue/steering rules.
- [Part 2g: Agent Status and Lifecycle](plan/part2g-status-and-lifecycle.md) — Reactive agent status, stopping/interrupting, agent lifecycle detection.
- [Part 2h: Permissions](plan/part2h-permissions.md) — Permission model, auto-trust, permission modes, plan mode behavior, reconfigure-session flow.
- [Part 2i: Session Storage](plan/part2i-session.md) — Session map, SessionManager, persisted session IDs, session lifecycle.

**Part 3: Features and Data Model**
- [Part 3a: Projects and Threads](plan/part3a-projects-and-threads.md) — Projects, project creation, thread creation, thread management, archiving.
- [Part 3b: Git Operations](plan/part3b-git.md) — GitService, CLIGitService, FileListManager.
- [Part 3c: GitHub and Worktrees](plan/part3c-github-and-worktrees.md) — GitHub integration, GitHubCLIService, worktrees, branching, PR discovery.
- [Part 3d: Diff Viewer](plan/part3d-diff-viewer.md) — Diff viewer pane, DiffViewerViewModel, file watching, staging/unstaging, agent-directed commit/PR actions.
- [Part 3e: Skills](plan/part3e-skills.md) — Skills service, skills catalog, skills.sh integration.
- [Part 3f: Skills Service](plan/part3f-skills-service.md) — DefaultSkillsService concrete implementation.
- [Part 3g: MCP](plan/part3g-mcp.md) — MCP service, adapters, config I/O, MCP server management.

**Part 4: User Interface**
- [Part 4a: Layout](plan/part4a-layout.md) — App entry point, NavigationSplitView, middle pane, right pane, visual design.
- [Part 4b: Sidebar](plan/part4b-sidebar.md) — SidebarViewModel, SidebarView, sidebar selection binding.
- [Part 4c: Chat View](plan/part4c-chat.md) — Chat ownership, rendering structure, banners, and composer integration.
- [Supplement: Composer State and Live Progress](plan/supplement-composer-and-live-progress.md) — Composer state matrix, setting wiring, `StreamingBubble`, input-bar states, and live progress.
- [Part 4d: Chat Blocks and Tool Rendering](plan/part4d-chat-blocks.md) — Working blocks, tool rendering (Read, Edit, Write), sub-agent blocks, task list, prompt blocks, and markdown rendering.
- [Supplement: Chat Input and Interactions](plan/supplement-chat-input-and-interactions.md) — `ChatInputField`, autocomplete, queueing UI, steering, scroll behavior, and chat performance.
- [Part 4e: Screens and Lifecycle](plan/part4e-screens-and-lifecycle.md) — Screen integration, error handling, first-run experience, keyboard shortcuts, app lifecycle.

**Validation**
- [Validation](plan/validation.md) — Assumptions and architecture decisions that have been tested or need testing before implementation.
- [Validation History](plan/validation-history.md) — Resolved follow-up validations and plan-audit findings that informed later plan revisions.

Implementation-readiness note: the plan has completed the validation/audit sweep recorded in the two documents above and is sequentially buildable as written. Start implementation at Phase 1, preserve the documented bootstrap/runtime/lifecycle contracts, and treat the remaining validation work as limited to implementation-time manual checks plus future-provider contracts.

## Build phases

Each phase ends at a compilable checkpoint. Build each phase's sections in order, run tests before moving to the next phase.

Progress tracking rules:
- Update the phase checkbox in this file as soon as that phase's checkpoint is actually complete in the repo.
- Also update the matching detailed `plan/part*.md` status checklist for the work you finished so future sessions can resume from the docs instead of thread history.

### Phase 1: Project scaffolding and data layer
- [x] Complete

Generate the Xcode project, add SPM dependencies, and define the data models. No business logic yet.

| Section | What to build |
|---|---|
| Xcode Project Generation | Create `project.yml`, `knitconfig.json`, `.gitignore` additions. Run `xcodegen generate`. |
| Dependency Management: SPM | Verify all SPM packages resolve (declared in `project.yml`) |
| Library Stack | Verify all libraries resolve (build check) |
| Project Structure | Create folder structure per the tree diagram |
| App Bootstrap Stub | Add a minimal single-window `@main` `SkepApp` plus an empty `AppDelegate` shell wired through `@NSApplicationDelegateAdaptor`, using `Window("Skep", id: "main") { EmptyView() }`, so the application target compiles before the real UI lands in Phase 6 |
| Dependency Injection: Knit | Create the app-level `Resolver`, one empty `ModuleAssembly` — verify Knit codegen works |
| App Database | Define all 4 SwiftData `@Model` classes, `DataAssembly` (registers `ModelContainer` + `ModelContext` via Knit), and add a tiny in-memory SwiftData smoke suite that resolves the container, inserts every model type, verifies `Project.path` uniqueness, and verifies cascade delete |

**Checkpoint**: application target builds with the placeholder window scene, SwiftData models, and Knit wiring. No real UI yet.

### Phase 2: Settings, utilities, and core types
- [x] Complete

Build the types everything else depends on: settings, shell runner, event model, and concurrency building blocks.

| Section | What to build |
|---|---|
| App Settings | `AppSettings`, `SettingsService` protocol + `UserDefaultsSettingsService` + `InMemorySettingsService`, `SkepProjectConfig`, `SettingsViewModel`, and `SettingsAssembly` for the service layer |
| App Session State | `AppState`, `SidebarItem`, `SidebarBookmark`, `CommandRequest`, `DiffActionRequest`, and selected-conversation helpers — pure launch-scoped UI state with no view dependencies, built early so Phase 6 sidebar/chat/layout wiring shares one owner instead of inventing placeholders later |
| Shell Runner | `ShellResult`, `ShellRunner` protocol + `DefaultShellRunner` + `MockShellRunner`, Knit assembly, plus focused integration coverage for timeout / cancellation / bounded-output behavior |
| Universal Event Model (Part 1e) | `ConversationEvent` enum with `toRecord()`, `AgentConfig`, `AgentSpawnConfig`, `AgentError`, `NotificationManager` protocol + `DefaultNotificationManager`. |
| Concurrency Model | Establish `@MainActor`, `Sendable`, and task-ownership conventions — no new types, just rules carried into later phases |
| Diff Parser | `DiffFile`, `DiffHunk`, `DiffLine`, `DiffParser` — pure parsing utility, no dependencies |

**Checkpoint**: settings persist, shell commands run, event types exist. All unit tests pass.

### Phase 3: Agent integration
- [x] Complete

Build the provider system and agent process management. This is the core engine. **Build in this order** — each row depends only on rows above it.

Phase 3 progress:
- [x] Steps 1-10 and 15 are implemented in the repo: provider registry/detection, environment builder, turn/message queue, session storage, event grouping, `DefaultAgentsManager`, `EventBuffer`, `ClaudeAdapter`, and lifecycle/status plumbing.
- [x] Focused regression coverage exists for the new runtime layer (`ClaudeAdapterTests`, `EventBufferTests`, `AgentsManagerTests`) in addition to the earlier provider/session tests.
- [x] Step 12 (`ProviderSetupService` / `ClaudeConfigStore`) is implemented with serialized Claude config writes and focused setup/config-store coverage.
- [x] Step 13 (`ConversationViewModel` + setup/send/replay wiring) is implemented with the placeholder `WorktreeManager`, auto-naming helpers, and focused VM coverage.
- [x] Step 14 permission-mode and effort reconfigure verification is covered by focused adapter/runtime/VM regression tests.
- [x] Broader targeted validation passed for the Phase 3 surface area (`AgentsManagerTests`, `EventBufferTests`, `ClaudeAdapterTests`, `ConversationViewModelTests`, `ProviderSetupServiceTests`, `ProviderDetectionServiceTests`, `ProviderRegistryTests`, `SessionManagerTests`, `ClaudeConfigStoreTests`, `ShellRunnerTests`, `ChatItemGrouperTests`, `ConversationEventTests`).

| # | Section | What to build |
|---|---|---|
| 1 | Provider Adapters | `AgentAdapter` protocol |
| 2 | Shared Agent Registry + Provider Registry | `AgentDefinition`, `AgentRegistry` protocol + `DefaultAgentRegistry`, then `ProviderRegistry` protocol + `DefaultProviderRegistry` (provider projection over the shared registry) |
| 3 | Provider Detection and Installation | `ProviderDetectionService` protocol + `DefaultProviderDetectionService` (depends on `ShellRunner`, `ProviderRegistry`, `SettingsService` for custom CLI overrides) |
| 4 | Environment Variables | `AgentEnvironmentBuilder` protocol + `DefaultAgentEnvironmentBuilder` |
| 5 | Turn State and Message Queue | `TurnState`, `QueuedMessage`, `MessageQueue` — simple types with no dependencies |
| 6 | Activity Classification | `ActivitySignal` enum — no dependencies, needed by `DefaultAgentsManager` |
| 7 | Session Storage and Resuming (Part 2i) | `SessionManager` protocol + `DefaultSessionManager` — needed by `DefaultAgentsManager`. Public reads lazily `ensureLoaded()` so resume correctness does not depend on startup timing. Persist the validated binding shape up front: conversation ↔ provider metadata plus canonical cwd, current resumable session ID, and last-launched argv session ID so fork-session recovery and Phase 7 orphan cleanup do not require a later schema change. |
| 8 | Event Grouping | `ChatItem`, `ToolEntry`, `SubAgentEntry`, `TaskEntry`, `ChatItemGrouper` — pure data transformation, needed by `ConversationState` |
| 9 | Agent Process Spawning (Parts 2c + 2d) | `AgentsManager` protocol + `DefaultAgentsManager` actor with the standalone `ConversationState` runtime type (Part 2c), `EventBuffer`, spawn/subscribe/markPersisted from [Part 2d](plan/part2d-spawn-and-buffer.md), and stdin delivery / kill / reconfigure / exit cleanup from the [Agent Runtime Teardown supplement](plan/supplement-agent-runtime-teardown.md). Also create `SetupPhase` from the [ConversationViewModel Behaviors supplement](plan/supplement-conversation-viewmodel-behaviors.md) in `Skep/Utilities/SetupPhase.swift` so `ConversationState.setupPhase` is available before `ConversationViewModel` itself is built at #13. Includes `.agentStatusChanged`, `.managedProcessesChanged`, `statusSnapshot`, the lock-protected `allProcessesSnapshot`, nonisolated `status(for:)`, `clearStatus(for:)`, and `beginShutdown()` for Phase 7 shutdown safety. A freshly spawned long-lived process with no in-flight turn starts in `.idle`, not `.busy`. Stub `resolveAdapter()` with `fatalError("TODO")` — filled in at #10. |
| 10 | ClaudeAdapter + Turn Lifecycle | `ClaudeAdapter` (depends on `AgentAdapter` #1) — implement and wire into `DefaultAgentsManager.resolveAdapter()` |
| 11 | Streaming Pipeline | Already built as part of `DefaultAgentsManager.readAgentOutput()` |
| 12 | Provider Setup Service | `ClaudeConfigStore` protocol + `DefaultClaudeConfigStore` actor, then `ProviderSetupService` protocol + `DefaultProviderSetupService` actor — provider-specific pre-spawn setup (config files, trust entries). `ClaudeConfigStore` is the sole serialized writer for Claude-owned config files; higher-level services orchestrate through it rather than performing parallel file writes themselves. Needed by `ConversationViewModel` #13 and later reused by MCP config writes in Phase 5. |
| 13 | ConversationViewModel | `ConversationViewModel` (depends on `AgentsManager`, `ConversationState`, `ChatItemGrouper`, `ModelContext`, `SettingsService`, `WorktreeManager` protocol, `ProviderSetupService`). Core agent lifecycle methods (`startAgent`, `send`, `subscribe`, `handleEvent`, `queueOrSend`, `steer`, `reconfigureSession`) live in [Part 2f](plan/part2f-viewmodel.md); setup helpers, staged-context rules, auto-naming, and outbound routing live in the [ConversationViewModel Behaviors supplement](plan/supplement-conversation-viewmodel-behaviors.md). `startAgent` runs provider setup on every spawn path; queued messages drain on turn completion (not process EOF); first-time setup is keyed off persisted thread state, not in-memory replay counters. The first-message orchestration (`setupAndStart`) also lives here but references `WorktreeManager` — define the minimal placeholder protocol surface used here (`create(projectPath:threadName:baseRef:remoteName:)` and `remove(...)`) at this step, then expand it to the full protocol and wire `DefaultWorktreeManager` in Phase 4 / Part 3c. |
| 14 | Permissions and Permission Modes | CLI flag logic in `ClaudeAdapter.buildArgs()` for each permission mode. `reconfigureSession()` was already built at #9 — this step just verifies the full fork-session flow works end-to-end with different `--permission-mode` and `--effort` values. |
| 15 | Agent Status and Lifecycle (Part 2g) | Finish the observer-facing lifecycle contract on top of the status storage from #9: stop/interrupt paths, lifecycle detection, `.idle` / `.busy` / `.stopped` transitions, and the reactivity rules consumers follow when reading `.agentStatusChanged` / `.managedProcessesChanged`. |

**Checkpoint**: can spawn a Claude process, stream events, persist to SwiftData, send messages, and expose stable lifecycle status to later UI consumers. All unit tests pass.

### Phase 4: Git and GitHub services
- [x] Complete

Build the Git workflow layer. Each service depends on `ShellRunner`.

| Section | What to build |
|---|---|
| Git Operations | `GitService` protocol + `CLIGitService` (depends on `ShellRunner`), `FileListManager` protocol + `GitFileListManager` (depends on `GitService`) |
| GitHub Integration | `GitHubCLIService` protocol + concrete (depends on `ShellRunner`), `GitHubService` protocol + `CLIGitHubService` (depends on `GitHubCLIService`). Non-interactive device flow must parse the stdout URL/code and explicitly open the browser from the app — `gh auth login --web` does not auto-open it without a TTY. |
| Git Worktrees | Expand the Phase 3 placeholder `WorktreeManager` protocol into the full API (preserve the Phase 3 remote-aware `create(projectPath:threadName:baseRef:remoteName:)` / `remove(...)` surface; add `createFromBranch(..., remoteName:)`, `deleteBranch()`, and `list()`), then implement singleton actor `DefaultWorktreeManager` (depends on `ShellRunner`, `SettingsService`) so worktree target resolution and cleanup cannot race each other. Worktree roots must be namespaced per project and base-ref / push logic must use `Project.remoteName` instead of assuming `origin`. |

**Checkpoint**: Git operations, worktree management, and GitHub auth all work via CLI. All unit tests pass.

**Manual validation gate**: verify the GitHub device-flow UX end-to-end from the app shell, including URL parsing, explicit browser launch, cancel/retry behavior, and reconnect after an auth loss.

### Phase 5: Feature services
- [x] Complete

Phase 5 progress:
- [x] Project import and thread lifecycle actions are implemented in `SidebarViewModel`, including remote-aware project metadata resolution, initial thread/main-conversation creation, archive/restore/delete flows, and focused view-model coverage.
- [x] Skills support is implemented with `DefaultSkillsService`, `SkillsViewModel`, bundled catalog fallback data, GitHub-backed `SKILL.md` resolution/caching, `skills.sh` search, and registry-derived per-agent sync state.
- [x] MCP support is implemented with `DefaultMCPService`, `MCPConfigIO`, bundled recommended servers, provider-aware availability metadata, and `MCPViewModel`.
- [x] Focused regression coverage passed for the remaining Phase 5 surface area (`SkillsServiceTests`, `SkillsViewModelTests`, `MCPConfigIOTests`, `MCPAdapterTests`, `MCPServiceTests`, `MCPViewModelTests`).

Build the remaining non-UI services.

| Section | What to build |
|---|---|
| Projects | Project creation logic (uses `SkepProjectConfig` from Phase 2), including preferred remote detection/persistence on `Project.remoteName` alongside `gitRemote`, `baseRef`, and GitHub metadata |
| Thread Creation Flow | Thread lifecycle logic (create, archive, restore, delete). The first-message orchestration (`ConversationViewModel.setupAndStart()`) was built in Phase 3 #13; this step verifies the full end-to-end flow with a real `DefaultWorktreeManager` (from Phase 4). |
| Skills (Parts 3e + 3f) | `SkillsService` protocol (Part 3e) + `DefaultSkillsService` (Part 3f), `SkillsViewModel`, and the per-agent sync state surfaced on each `Skill` |
| MCP | `MCPService` protocol + `DefaultMCPService` (reuses `ClaudeConfigStore` as the sole serialized Claude-config writer plus `ProviderDetectionService`), `MCPViewModel`, and the richer per-agent availability metadata used by the add/edit form |

**Checkpoint**: all service protocols have concrete implementations. All unit tests pass.

**Future-provider gate**: before adding any non-Claude provider work beyond registry placeholders, validate that provider's session and permission-mode contracts from [plan/validation.md](plan/validation.md) so shared runtime/UI abstractions do not assume Claude semantics by accident.

### Phase 6: User interface
- [x] Complete

Build all views, wiring them to the services and view models from earlier phases. **Build in this order** — shared error/empty-state components land before views that render them, `ContentView` creates `SidebarViewModel` and `DiffViewerViewModel`, and `ConversationView` also depends on `DiffViewerViewModel`, so the diff-viewer types must exist before the chat views and app layout are wired.

Phase 6 progress:
- [x] `SidebarViewModel` is implemented, including project/thread create/archive/restore/delete actions, aggregate thread-status computation, and shared sidebar error/status observation state.
- [x] The repository-scoped `DiffViewerViewModel` foundation is implemented, including refresh coalescing, FSEvents/poll watcher management, contextual commit/PR action state, selected-diff loading, and focused regression coverage.
- [x] The chat composer input-handling slice is implemented: selection-aware `@` file autocomplete, `/skill` autocomplete, keyboard-driven suggestion selection, drag-and-drop file insertion, and send-time `@path` normalization.
- [x] Snapshot coverage now includes higher-level Phase 6 pane surfaces (`SidebarView`, `DiffViewerPane`) in addition to the composer states, chat blocks, and secondary screens.
- [ ] The manual diff-viewer watcher validation gate remains open in `plan/validation.md` and is tracked separately from the phase checkpoint.

| Section | What to build |
|---|---|
| Error Handling UX | `InlineBanner`, `EmptyStateView` from [Part 4e](plan/part4e-screens-and-lifecycle.md) |
| Sidebar | `SidebarView`, `SidebarViewModel` |
| Diff Viewer | `DiffViewerPane`, `DiffViewerViewModel` (FSEvents watcher), repository binding state (`directory`, `baseRef`, `remoteName`, `conversationIds`), contextual action state, refresh coalescing, and the `onCommitRequested` / `onOpenPRRequested` callback surface. The actual `AppState.pendingDiffAction` handoff is wired in App Layout once both `ContentView` and `ConversationView` exist. |
| Chat View Architecture (Parts 4c + 4d) | `ThreadDetailView`, `ConversationTabs`, `ConversationView`, `ChatView`, the base `ChatInputField`, and the core banner/scroll structure from [Part 4c](plan/part4c-chat.md). `StreamingBubble`, composer state wiring, and live progress come from the [Composer State and Live Progress supplement](plan/supplement-composer-and-live-progress.md). All block components: `WorkingBlock`, `SubAgentBlock`, `TaskListBlock`, `PromptBlock`, `ThinkingBlock`, `ErrorBanner` (Part 4d). Bubble components: `UserBubble`, `AssistantBubble`, `QueuedMessageBubble`. Leave richer `@`-mention, `/skill`, queue-affordance, and drag-and-drop behaviors for the later **Input and Message Handling** step. (`ChatItemGrouper` already built in Phase 3). |
| Skills Screen | `SkillsScreen`, skill cards, skill detail modal, create form |
| MCP Screen | `MCPScreen`, server list, add/edit form |
| Project Settings | `ProjectSettingsView` (project name, base ref, setup/teardown scripts, actions — layout from Part 3a) |
| Settings Screen | `SettingsScreen`, tab content views |
| Input and Message Handling | Extend the base `ChatInputField` from the earlier chat-architecture step with the behaviors documented in the [Chat Input and Interactions supplement](plan/supplement-chat-input-and-interactions.md): @-mention popup, /skill popup, queue/steer affordances, and drag-and-drop file attachment |
| First-Run Experience | Empty state views for each screen from [Part 4e](plan/part4e-screens-and-lifecycle.md) |
| App Layout | Replace the Phase 1 placeholder `SkepApp` scene with the real app shell: `SkepApp` (single `Window` scene), `ContentView` (wires resolver to VMs), `MiddlePane`, the validated two-column `NavigationSplitView` + conditional right-pane `HStack` layout (not native three-column visibility control on macOS 26), and the concrete diff-action handoff (`DiffViewerPane` callbacks → `AppState.pendingDiffAction` → matching `ConversationView`). Reuse the Phase 1 `AppDelegate` shell; Phase 7 fills in its startup/shutdown behavior. Built last — depends on all VMs and views above. |
| Keyboard Shortcuts | `.keyboardShortcut()` modifiers |

**Checkpoint**: full app runs end-to-end. Snapshot tests pass.

**Manual validation gate**: run the integrated diff-viewer watcher pass after the real UI exists — start/stop watching, debounce around atomic writes, selected-file invalidation, idle-poll fallback, and pane teardown after the early `.appWillTerminate` notification.

### Phase 7: App lifecycle and polish
- [x] Complete

Phase 7 progress:
- [x] `AppDelegate` now owns startup warmup, wake-refresh throttling, `.appWillTerminate` emission, sudden-termination toggling, and session-map-driven orphan cleanup.
- [x] Focused lifecycle regression coverage exists in `AppDelegateTests` for startup warmup, orphan cleanup ownership checks, wake refresh cancellation, sudden-termination transitions, and orderly shutdown persistence.
- [ ] The signed-app notification delivery manual validation gate in `plan/validation.md` remains open.

| Section | What to build |
|---|---|
| App Lifecycle | Fill in `AppDelegate` startup/shutdown sequences, owned warmup/wake-refresh task cancellation, early `.appWillTerminate` notification emission for view-model teardown, the inline main-actor shutdown hop required by that notification path, sudden-termination disable/enable windows, best-effort crash/termination cleanup, and orphan-process cleanup using `SessionManager` as the source of truth. The minimal `AppDelegate` type already exists from Phase 1 so the app remains compilable throughout. |

**Checkpoint**: app launches, runs agents, and shuts down cleanly.

**Manual validation gate**: once the signed app target exists, verify notification authorization timing plus granted/denied persistence and actual delivery/display behavior for the `NotificationManager` surface.
