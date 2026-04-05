# Part 3a: Projects and Threads

Projects, project creation, thread creation, thread management, archiving. Depends on Parts 1-2.

## Projects

A project is a Git repository that contains one or more threads. It's the top-level grouping concept.

### What a Project Tracks

- **Path** -- the local filesystem path to the repo (unique identifier).
- **Git info** -- preferred remote name + remote URL, current branch, base ref (the branch worktrees branch from, e.g. `main`).
- **GitHub info** -- `owner/repo` string, whether GitHub is connected (for PR/CI features).

**Remote invariant**: `Project.remoteName` and `Project.gitRemote` are stored together. Later Git/worktree services must use that persisted `remoteName` instead of rediscovering "whatever remote looks right" at call time, so base-ref resolution, ahead-of-base comparisons, and push/publish flows all stay consistent on multi-remote repositories.

### Project-Level Configuration File

Per-project settings live in a JSON config file in the repo root. Since it's committed to the repo, it's shared with the team. Filename: `.skep.json`.

```json
{
  "scripts": {
    "setup": "npm install && npm run build",
    "teardown": "docker compose down"
  },
  "shellSetup": "source .venv/bin/activate && export DATABASE_URL=postgres://localhost/dev",
  "preservePatterns": [".env", ".env.local", ".env.development"],
  "actions": [
    { "name": "Run app", "command": "npm start" }
  ]
}
```

- **`scripts.setup`** -- shell command run in the worktree after creation, before the agent starts. The agent process blocks until this completes. Common uses: install dependencies, run migrations, start Docker services.
- **`scripts.teardown`** -- shell command run before worktree destruction. Common uses: stop services, clean up containers, release ports.
- **`shellSetup`** -- **reserved for future use.** Intended to be sourced in every agent process before the CLI executes (inline shell setup, not a separate process). Common uses: activate virtualenvs, set environment variables, extend PATH. **Not yet applied at spawn time** — the spawn pipeline launches the CLI directly via `Process()` without a shell wrapper. To implement, the spawn would need to either wrap the CLI in `/bin/sh -c "source <setup> && <cli> <args>"` or pre-evaluate the setup script and inject resulting environment variables. Deferred to post-v1 due to complexity (virtualenv activation modifies PATH, VIRTUAL_ENV, etc. — cannot be reduced to static env vars). The field is parsed by `SkepProjectConfig` so the config format is stable; use `scripts.setup` for worktree initialization until `shellSetup` is implemented.
- **`preservePatterns`** -- glob patterns for gitignored files to copy from the main repo into new worktrees. Without this, `.env` files with secrets wouldn't exist in the worktree since they're not committed.
- **`actions`** -- array of `{ "name": "...", "command": "..." }` objects. Each action appears as a button in the project toolbar. Clicking it runs the shell command in the active thread's working directory.

### Accessing Project Settings in the UI

Project settings are accessed by clicking on the project name in the left sidebar. This opens a project settings panel in the middle pane:

```
┌─ Environments ──────────────────────────────────────────┐
│                                                         │
│  Project                                                │
│  ┌─────────────────────────────────────────────────────┐│
│  │ 📁 my-app                                          ││
│  │    /Users/you/Development/my-app                    ││
│  └─────────────────────────────────────────────────────┘│
│                                                         │
│  Environment details                                    │
│  ┌──────────────────────────────────────────┐           │
│  │ Name                           my-app    │           │
│  └──────────────────────────────────────────┘           │
│                                                         │
│  Repository                                              │
│  Base branch                     main                    │
│  GitHub repo                     afollestad/skep         │
│                                                         │
│  GitHub                                                 │
│  Connected for PR/CI features and agent-opened PRs.     │
│                                        [ Connected ]    │
│                                                         │
│  AI agents                                              │
│  Claude Code                                            │
│  ┌──────────────────────────────────────────┐           │
│  │ curl -fsSL https://claude.ai/install...📋│           │
│  └──────────────────────────────────────────┘           │
│                                      [ ↻ Refresh ]      │
│                                                         │
│  Setup script                                           │
│  Runs on worktree creation.                             │
│  ┌──────────────────────────────────────────┐           │
│  │ npm install && npm run build          📋 │           │
│  └──────────────────────────────────────────┘           │
│                                                         │
│  Cleanup script                                         │
│  Runs before worktree deletion.                         │
│  ┌──────────────────────────────────────────┐           │
│  │ No cleanup script configured.             │           │
│  └──────────────────────────────────────────┘           │
│                                                         │
│  Actions                                                │
│  Custom commands shown in the header.                    │
│  ┌──────────────────────────────────────────┐           │
│  │ ▷  Run app                                │           │
│  └──────────────────────────────────────────┘           │
│                                                         │
│                          [ Edit local environment ]      │
└─────────────────────────────────────────────────────────┘
```

**Sections:**

- **Project**: read-only card showing the project name and filesystem path.
- **Environment details**: editable display name for the project.
- **Repository**: read-only Git metadata for the project, including the chosen remote name (`Project.remoteName`) when one exists, the detected default base branch (`Project.baseRef`) that new worktrees branch from, and the parsed GitHub repository identifier when the remote is on GitHub.
- **GitHub**: auth/status card for PR and CI features. If `githubConnected == false` but `gh` is installed, show the inline **"Connect GitHub"** CTA from Part 3c / Part 4e and start the device flow via `GitHubCLIService.authenticate()`. If the `gh` CLI is missing instead, replace the auth CTA with install guidance (`brew install gh`) rather than pretending a login can start.
- **AI agents**: inline provider-setup card driven by the shared `AgentRegistry` (for names/install commands/docs) plus `ProviderDetectionService` (for live status). When at least one provider is available, this section can collapse to a compact connected-status row. Only after the initial detection pass completes and **all checked providers** are `.missing` should this card switch into post-project install guidance: list each missing provider's `installCommand` from the matching `AgentRegistry` entry in a copyable code block and offer a **Refresh** button that calls `ProviderDetectionService.checkAllProviders()`. `.unchecked` is a real launch state and should render as loading/refreshing instead of as "not installed." This keeps the project settings visible instead of replacing the entire middle pane with a separate empty state.
- **Setup script**: the `scripts.setup` command from `.skep.json`. Shown in a code-styled field with a copy button. If not configured, shows placeholder text. "Available environment variables" link shows the injected lifecycle-script variables: `SKEP_THREAD_NAME`, `SKEP_PROJECT_PATH`, `SKEP_WORKTREE_PATH`, `SKEP_BRANCH_NAME`, and `SKEP_PORT_SEED`.
- **Cleanup script**: the `scripts.teardown` command from `.skep.json`. Same display pattern.
- **Actions**: custom commands defined in `.skep.json` that appear as buttons in the toolbar when this project's threads are active. Each action has a name and a shell command.
- **Edit local environment**: opens the `.skep.json` file in the user's default editor. If the file does not exist yet, the project settings footer also exposes a **Create Config** action that writes a valid JSON starter template first, then opens it. Do not write commented JSON — `.skep.json` must stay parseable by `JSONSerialization`.

**Dependency boundary**: `ProjectSettingsView` receives its collaborators explicitly from the layout layer — `GitHubCLIService` for auth flows, `ProviderDetectionService` for install/refresh status, and `AgentRegistry` for provider metadata. The screen should not rely on hidden resolver lookups from deep inside the view body, because this is the only project-level screen that mixes repo metadata with provider/GitHub integration state.

Minimal screen signature:

```swift
struct ProjectSettingsView: View {  // Skep/Views/Projects/ProjectSettingsView.swift
    let project: Project
    let gitHubCLI: GitHubCLIService
    let providerDetection: any ProviderDetectionService
    let agentRegistry: AgentRegistry
}
```

**Snapshot tests for ProjectSettingsView:** cover the normal configured state plus the high-variance setup cards. Non-obvious:
- GitHub connected vs `gh` installed-but-disconnected vs `gh` missing
- AI-agents card with at least one connected provider vs the all-missing install-guidance state
- Setup/cleanup script rows present vs placeholder-empty state
- Config-missing footer state showing **Create Config**

### Project-to-Thread Relationship

```
Project (~/Development/my-app)
  ├── Thread A (worktree: ../worktrees/my-app-9c4f21/fix-auth-a2b/, branch: app/fix-auth-a2b)
  │     ├── Conversation 1 (main, session abc-123)
  │     └── Conversation 2 (side chat, session def-456)
  ├── Thread B (worktree: ../worktrees/my-app-9c4f21/add-tests-c3d/, branch: app/add-tests-c3d)
  │     └── Conversation 1 (main, session ghi-789)
  └── Thread C (archived, worktree on disk)
```

Each thread gets its own worktree (isolated copy of the repo), its own branch, and one or more agent conversations. The project's base ref determines what each thread branches from.

---

## Project Creation Flow

When the user clicks the `+` button next to "Projects" in the sidebar:

1. **Select folder** -- file picker (`NSOpenPanel`) to choose a local Git repository.
2. **Detect Git and preferred remote** -- run `git rev-parse --show-toplevel` to confirm it's a repo and get the root path. Then resolve the preferred remote name once: use the current branch's upstream remote when it exists, otherwise use the sole configured remote, otherwise fall back to `origin` only as an ambiguity-breaking compatibility fallback. If no safe choice exists, persist `remoteName = nil` and treat the repository as local-only for remote-dependent features. When a remote was chosen, run `git remote get-url <remoteName>` and persist both `Project.remoteName` and `Project.gitRemote`; local-only repositories remain valid projects with both fields nil.
3. **Read config** -- check for `.skep.json` in the repo root. If present, parse it via `SkepProjectConfig(projectPath:)` (defined in `Skep/Services/Settings/SkepProjectConfig.swift`) for `shellSetup`, `scripts`, `preservePatterns`, `actions`.
4. **Detect GitHub** -- if the chosen remote URL parses as GitHub, extract `owner/repo`. Check `gh auth status` only when `gh` is installed; otherwise persist `githubConnected = false` without failing project creation.
5. **Resolve base ref** -- when `remoteName` is set, prefer `git symbolic-ref refs/remotes/<remoteName>/HEAD` to detect that remote's default branch (e.g. `main`, `master`). If that remote HEAD is unavailable, fall back to `git rev-parse --abbrev-ref HEAD` so local-only repositories and partially configured remotes still get a usable `Project.baseRef`.
6. **Save to SwiftData** -- create a `Project` record with path, name (last path component), `remoteName`, remote URL, branch, base ref, and GitHub info.
7. **Show in sidebar** -- the project appears in the left pane. Clicking it shows project settings in the middle pane.

If the project has no `.skep.json`, the project settings screen should offer a "Create Config" button that writes a valid JSON template (for example, empty `scripts` / `actions` scaffolding plus default `preservePatterns`) before opening it.

---

## Thread Creation Flow

When the user clicks the `+` button next to a project in the sidebar, or clicks "New thread" at the top of the sidebar, a new thread is created and the empty chat view is shown immediately:

```
┌─────────────────────────────────────────────────────────────┐
│  New thread                                                 │
│                                                             │
│                                                             │
│                                                             │
│                          (icon)                             │
│                        Let's build                          │
│                        my-project                           │
│                                                             │
│                                                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Ask anything, @ to add files, / for skills          │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │  🔷 Opus ▾   ⚡ High ▾   🔒 Default ▾      ⬆  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  📂 Local      ⚙ Config                     🌿 base: main   │
└─────────────────────────────────────────────────────────────┘
```

**Layout breakdown:**

- **Header**: "New thread" title.
- **Center**: App icon, "Let's build" heading, project name as read-only context for the thread that was just created from the sidebar action.
- **Input bar**: multiline text input with placeholder showing available affordances (`@` for files, `/` for skills). Below the input: model picker dropdown (e.g. "Opus", "Sonnet" -- passed to the CLI via `--model`), effort dropdown (e.g. "High ▾" -- only visible when the provider's `supportedEffortLevels` is non-nil), permission mode dropdown, and send button. Files and images can be attached via `@`-mention or drag-and-drop into the input area.
- **Status bar** (bottom): read-only worktree-mode indicator (Local / Worktree), config file link, and the project's current base ref. v1 does not support pre-send project switching or branch/base-ref overrides from this screen.

The thread is not actually spawned until the user sends the first message. Steps 1-9 below happen on first message send:

1. **Resolve provider, model, effort, and permission mode** -- the provider was already seeded onto the initial `Conversation` from `AppSettings.defaultProvider` when the thread/conversation was created, so v1 only exposes model / effort / permission pickers in the pre-send UI. `effort` and `permissionMode` are seeded from `AppSettings` and stored on the `AgentThread` because they apply across that thread's worktree/session lifecycle. The model picker is conversation-scoped and defaults to `"Default"` (no `--model` flag, letting the CLI choose). When the user selects a concrete model, it is passed to the CLI via `--model` (e.g. `--model opus`, `--model sonnet`). The CLI accepts aliases (`opus`, `sonnet`, `haiku`) or full model IDs (`claude-opus-4-6`). There is no CLI command to enumerate available models, so the app maintains a static list of known aliases. A "Custom..." option allows entering a full model ID. The `system/init` event's `model` field confirms which model is active after spawn.
2. **Create worktree** (if enabled) -- create a worktree via `WorktreeManager.create()`. The slug passed to worktree/branch creation is derived from the first message via the same naming helper used for auto-naming, with a fallback to the current placeholder thread name. This keeps the operational branch/worktree names meaningful even though the visible thread title is only persisted later. `WorktreeManager` places the directory inside a project-specific namespace under `../worktrees/` so sibling clones with the same folder name cannot collide. If that slug/hash candidate already exists inside the project's namespace, `WorktreeManager` appends a numeric suffix (`-2`, `-3`, ...) to the operational branch/worktree name so repeated threads with identical first messages still get unique Git/worktree targets. Run the project's `scripts.setup` if configured. During creation, the empty chat view replaces the "Let's build" heading with a progress indicator:

```
┌─────────────────────────────────────────────────────────────┐
│  New thread                                                 │
│                                                             │
│                                                             │
│                       ◐  Setting up...                      │
│                       Creating worktree                     │
│                                                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Ask anything, @ to add files, / for skills          │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │  🔷 Opus ▾   ⚡ High ▾   🔒 Default ▾      ⬆  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  📂 Worktree   ⚙ Config                   🌿 base: main    │
└─────────────────────────────────────────────────────────────┘
```

The spinner and status text update through the setup phases: "Creating worktree" (includes any setup script run by `WorktreeManager`) → "Starting agent". The input bar is disabled until the agent process is ready. If worktree creation fails, show an error inline with a "Retry" button.

3. **Provider-specific setup** -- runs inside the shared `startAgent()` path before every spawn (initial spawn, respawn, reconfigure). For Claude this ensures `.claude/settings.local.json` exists and optionally writes a trust entry to `~/.claude.json` when the thread is using a worktree. The step is intentionally best-effort and silent in v1: it should not block the chat from starting by itself.
4. **Bind session** -- reconcile the session-map entry with the current cwd/provider and persist the active UUID before launching the process. If the conversation moved to a different working directory or provider, rotate to a fresh UUID before spawn.
5. **Spawn agent process** -- start the agent CLI via `Process` with piped stdin/stdout, structured output flags, session isolation args, environment variables, and the working directory set to the worktree.
6. **Persist reusable setup completion** -- once the first spawn succeeds and the reusable worktree/runtime metadata has been saved, set `AgentThread.hasCompletedInitialSetup = true`. This marker means "the next retry can reuse the existing bootstrap"; it does **not** mean the first turn already produced visible chat history. If saving the marker fails, roll back the just-created runtime/worktree state **and restore `hasCompletedInitialSetup = false` before the rollback save** so restore/relaunch cannot misclassify the thread as set up after cleanup already ran. Because that rollback uses destructive `destroyRuntime()`, the VM must then rebind a fresh `ConversationState` from `AgentsManager` and restore retry-critical UI fields (draft/model/staged context) before showing the empty-thread retry state again.
7. **Send the first message** -- write the user's input to the agent's stdin. This stays inside the same first-message failure boundary as step 6: if the first outbound transport write fails before the first turn actually starts, successful cleanup must restore `hasCompletedInitialSetup = false`; if cleanup itself fails and the just-created worktree is intentionally preserved for reuse, keep `hasCompletedInitialSetup = true` and leave the centered Retry UI keyed off "no history yet + `lastTurnError`" instead of forcing the thread back through worktree creation.
8. **Auto-name** -- if enabled, persist the visible thread title from the first message (see "Auto-Naming from First Message" in `supplement-conversation-viewmodel-behaviors.md` for validation rules and truncation logic). This reuses the same candidate string already used for worktree/branch slugging in step 2 when possible.
9. **Show in sidebar** -- the thread appears under its project with a busy indicator.

**Two independent invariants**:
- `hasCompletedInitialSetup` answers whether the thread already owns reusable worktree/runtime bootstrap state for its next spawn.
- The centered empty-thread Retry owner answers whether the user has any persisted/live chat content yet. A first-message failure can therefore leave `hasCompletedInitialSetup == true` while the UI still shows the pre-history Retry card.

### First-Message Setup State Summary

| UI moment | `setupPhase` | Center content | Input state |
|---|---|---|---|
| Brand-new empty thread before the first send | `nil` | "Let's build" intro state | Enabled |
| Worktree creation and project setup script | `.creatingWorktree` | Spinner + "Creating worktree" | Disabled |
| Provider setup and process spawn | `.startingAgent` | Spinner + "Starting agent" | Disabled |
| Setup or first-send failed before any history was persisted (including preserved-worktree cleanup failures) | `nil` | Centered setup-error card with Retry / install CTA | Enabled, with the original first message still preserved in `ConversationState.inputDraft` |

Example naming reuse on the first send:
- First message: `Refactor auth token refresh race in login flow`
- Visible thread title after auto-name: `Refactor auth token refresh race in login flow`
- Worktree / branch slug used earlier in setup: `refactor-auth-token-refresh-race-in-login-flow`

If another thread already claimed that operational name, the visible title can stay identical while the Git/worktree target is disambiguated as `refactor-auth-token-refresh-race-in-login-flow-2`.

### Thread Creation Sequence Diagram

```
User                ConversationVM      WorktreeManager     AgentsManager       SessionManager
  │                      │                    │                   │                   │
  │  Send first message  │                    │                   │                   │
  ├─────────────────────▶│                    │                   │                   │
  │                      │  create()          │                   │                   │
  │                      ├───────────────────▶│                   │                   │
  │                      │                    │  fetch, worktree  │                   │
  │                      │                    │  add, copy .env,  │                   │
  │                      │                    │  run setup script │                   │
  │                      │  WorktreeInfo      │                   │                   │
  │                      │◀───────────────────┤                   │                   │
  │                      │                    │                   │                   │
  │                      │  (failure: remove worktree, show Retry)                    │
  │                      │                    │                   │                   │
  │                      │  spawn(id, config) │                   │                   │
  │                      ├───────────────────────────────────────▶│                   │
  │                      │                    │                   │  createEntry()    │
  │                      │                    │                   ├──────────────────▶│
  │                      │                    │                   │                   │ persist()
  │                      │                    │                   │  sessionId(for:)   │
  │                      │                    │                   ├──────────────────▶│
  │                      │                    │                   │  UUID              │
  │                      │                    │                   │◀──────────────────┤
  │                      │                    │                   │                   │
  │                      │                    │                   │  Process.run()    │
  │                      │                    │                   │  readAgentOutput()│
  │                      │  subscribe()       │                   │                   │
  │                      ├───────────────────────────────────────▶│                   │
  │                      │                    │                   │                   │
  │                      │  sendMessage()     │                   │                   │
  │                      ├───────────────────────────────────────▶│                   │
  │                      │                    │                   │  stdin JSON write │
  │                      │                    │                   │                   │
  │                      │  auto-name, persist user record, beginTurn()              │
  │                      │                    │                   │                   │
  │  UI: busy indicator  │                    │                   │                   │
  │◀─────────────────────┤                    │                   │                   │
```

**Rollback on failure**: if worktree creation or agent spawn fails, the worktree is removed via `WorktreeManager.remove()` and the error is shown inline. The persisted `hasCompletedInitialSetup` flag stays `false` until the reusable spawn/worktree metadata is safely saved, and any later failure must either restore it to `false` after successful cleanup or intentionally keep it `true` when cleanup failed and the already-created worktree is being preserved for reuse. The session map entry is cleaned up by `spawn()`'s catch block. Because `destroyRuntime()` also destroys `ConversationState`, the VM cancels the failed runtime's local subscription/save tasks, rebinds a fresh state object from `AgentsManager`, restores the preserved draft/model/staged-context fields, and then shows the empty thread view with a "Retry" button. That centered retry owner is keyed to the lack of persisted/live chat content plus `lastTurnError`, not strictly to `needsSetup`, so the preserved-worktree path still lands in the same UI even though its retry will respawn against the surviving worktree.

**Spawn failure UI** — shown when worktree creation or agent spawn fails:

```
┌─────────────────────────────────────────────────────────────┐
│  New thread                                                 │
│                                                             │
│                                                             │
│                        ⚠ Setup failed                       │
│                                                             │
│          Agent process failed to start:                     │
│          CLI not found at /path/to/selected-provider         │
│                                                             │
│               [ Retry ]    Install Selected Provider...      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Ask anything, @ to add files, / for skills          │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │  🔷 Opus ▾   ⚡ High ▾   🔒 Default ▾      ⬆  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

The install action label and command come from the selected conversation provider's shared `AgentRegistry` entry (`installCommand`, `name`). In v1 this resolves to Claude Code, but the empty-state flow stays correct when future providers are added.

The error message is specific (CLI path, setup script error, etc.). "Retry" re-runs the full thread creation flow using the still-preserved first message from `ConversationState.inputDraft`; opening install guidance must not clear that draft. If the error is "CLI not found", a secondary link opens install guidance.

---

## Thread / Task Management

A thread groups one or more related agent conversations around a shared worktree/branch. Each conversation inside the thread can have its own provider session and live process. The key data tracked across the thread/conversation boundary is:

- **Thread ID** -- internal identifier.
- **Conversation provider** -- which CLI a given `Conversation` uses (Claude for the initial version; extensible to others).
- **Working directory** -- where the agent operates.
- **Branch** -- if using a worktree, which Git branch.
- **Agent session link** -- the mapping to Claude's session UUID, stored in the session map.

### Thread-to-Process Relationship

Each thread has one **agent process** per conversation (the Claude session). Processes are keyed by `conversation.id` (a UUID string) in all `AgentsManager` dictionaries (`processes`, `eventBuffers`, `conversationStatesStore`, `statusSnapshot`). The main conversation is marked `isMain: true` on the `Conversation` model; additional side chats have `isMain: false`.

Multiple conversations can exist per thread (e.g. a main chat and side chats), each with its own agent process and session isolation.

### Conversation Tab Switching

A thread can have multiple conversations (main + side chats), each with its own agent process. Conversations are shown as tabs at the top of the chat view:

```
┌────────────────────────────────────────────────────────┐
│  [ Main ●]  [ Research ]  [ Tests ○]            [+]   │ ← conversation tabs
├────────────────────────────────────────────────────────┤
│                                                        │
│  (chat content for the selected conversation)          │
│                                                        │
└────────────────────────────────────────────────────────┘
```

- The **active tab** has a bold label. Tabs show a status dot matching the conversation's live agent status (● busy, ○ idle, none for stopped or `.neutral`).
- The **selected tab** is tracked separately from sidebar selection in `AppState.selectedConversationIDs`, keyed by thread ID. The sidebar row stays selected on the thread while the middle pane remembers which conversation was last open for that thread within the current app session. `AppState.selectedConversation(in:)` treats that map as a best-effort bookmark, not a second source of truth: if the stored conversation ID no longer exists in the thread (for example after deletion, restore, or launch-scoped state reset), the pure read falls back to the main conversation, then the first conversation by `displayOrder`. The owning layout then calls `repairSelectedConversationIfNeeded(for:)` in an effect to rewrite the bookmark to that recovered ID. Only a truly empty thread returns `nil`.
- The **[+] button** creates a new side conversation (Cmd+T). It inserts a `Conversation` with `isMain = false`, the next `displayOrder`, and the current thread's active/default provider (copied from the main conversation unless the UI later offers an explicit override), then selects it immediately. The new conversation shares the thread's worktree and branch but does not spawn an agent until the user sends its first message.
- **All agent processes keep running.** Switching tabs doesn't kill or pause the background conversation's process.
- **The chat view swaps.** Each conversation has its own chat view backed by its SwiftData event history. Switching tabs loads the other conversation's events from the database and subscribes to its live event stream via `ConversationState`, which survives VM recreation within the current app session but is still reset by archive, `kill()`, or app relaunch.

### Thread Status in Sidebar

Each thread in the sidebar shows a status indicator derived from the structured event stream:

- **Busy** (pulsing dot or spinner) -- events are actively streaming from the agent process.
- **Idle** (static dot) -- the agent's turn is complete (received the Claude `result` event with `stop_reason: "end_turn"`), waiting for user input.
- **No dot** -- the conversation is stopped, or there is no live status entry yet (for example, never spawned or post-relaunch before respawn).
- **Archived** (dimmed) -- the thread is archived. No process running.

The status is tracked per-conversation but the sidebar shows the aggregate for the thread: busy if any conversation is busy, otherwise error if any conversation errored, otherwise idle if any conversation is waiting for input, otherwise no dot (`ThreadStatus.stopped`, including the all-`.neutral` pre-spawn/post-relaunch case).

---

## Thread Archiving and Worktree Cleanup

Threads support archive (soft delete) and permanent deletion, each with different worktree behavior.

### Archive (Preserves Worktree)

1. **Destroy each conversation runtime for the thread** -- iterate through every conversation in the thread and call `agentsManager.destroyRuntime(conversationId:)`. This is the single public owner for destructive teardown: it requests graceful shutdown (SIGTERM first, then SIGKILL after timeout if needed), waits for the runtime to disappear, and only then lets the manager-owned session-map removal finish. stdin is not closed explicitly; it closes when the child exits. The finished `EventBuffer` may linger briefly only for trailing durability grace, but restore/reopen still rely on durable SwiftData history because `ConversationState` is intentionally destroyed by explicit teardown. The sidebar-side quiesce helper should still attempt every conversation even if one teardown throws, then surface the first error after the full pass so a multi-conversation thread does not stay partially live.
2. Set `archivedAt` timestamp on the thread.
3. **Worktree is preserved on disk** -- directory stays, `git worktree list` still shows it, branch remains.
4. Thread record preserved in database with `path`, `branch`, conversations, metadata.

If archive fails after the UI has temporarily rehomed selection/bookmarks to the parent project, restore those UI bookmarks. The thread record is still present and selectable because `archivedAt` never persisted, but its runtime state may already have been quiesced (processes killed, session bindings cleared). Failing to restore the pre-archive UI context would still make the app forget which thread the user was looking at even though nothing was actually archived.

Archived threads appear in an "Archived" section in the UI. They can be restored or permanently deleted.

### Restore (Unarchive)

1. Set `archivedAt` back to null.
2. **Worktree is already there** -- no recreation needed. Code changes the agent made survive archiving, and `hasCompletedInitialSetup` stays true so restore does not re-run first-time setup.
3. No agent process is restarted during restore itself. The next user message follows the normal spawn path for the existing `Conversation`.
4. Previous Skep chat history remains visible from SwiftData, but the provider session is intentionally **fresh** in v1. Archiving calls `destroyRuntime()`, which removes the session-map entry as part of manager-owned destructive teardown, so restore does not attempt to resume the old Claude session. Conversation-scoped transient state owned by `ConversationState` (for example the selected model override) is likewise reset; persisted thread fields such as `effort` and `permissionMode` remain intact.
5. `AppState.selectedConversationIDs` is intentionally preserved across archive/restore within the same app session, so reopening the restored thread returns to the last selected conversation tab. App relaunch still resets that UI-only bookmark.

### Delete (Permanent -- the Only Time Worktrees Are Destroyed)

1. Everything from archive (destroy all runtimes, including manager-owned session-map removal), plus:
2. Delete every deferred orphan branch recorded in `pendingCleanupBranches` (skipping the thread's current live `branch` if the name was reused).
3. `git worktree remove <path>` -- current worktree deleted from disk.
4. Current branch deleted from Git.
5. Thread record and all related data cascade-deleted from database.

If worktree removal fails, abort the delete and keep the SwiftData thread record intact. The record is the only durable pointer to the worktree path/branch needed for a retry; deleting app state first would orphan cleanup.

**Important**: `destroyRuntime()` must be called for each conversation before the SwiftData cascade delete. It is the single public path that removes `ConversationState`, clears the visible runtime state, and waits for session-binding cleanup to finish. Both archive and delete flows call `destroyRuntime()` explicitly (see `SidebarViewModel.archiveThread()` and `deleteThread()`).

Worktrees are also cleaned up on **failed thread creation** (rollback) -- if worktree creation succeeds but a subsequent step fails, `destroyRuntime()` runs before `WorktreeManager.remove()` so the worktree is not deleted out from under a still-exiting child process.

Worktrees are **never** destroyed on archive. They're only destroyed on explicit delete or creation rollback.

### Key Design Decision

**Archiving preserves the worktree but destroys the live session binding.** Code changes survive, but the app does not proactively resume a live agent process and intentionally does not resume the old provider session on restore. This is safer than trying to restore stale process state automatically.

---
