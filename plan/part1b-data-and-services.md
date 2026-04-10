# Part 1b: Data and Services

App database, state management, settings, concurrency, shell runner, and service layer table. Continues from Part 1a.

## Implementation Status

- [x] App database
- [x] State management
- [x] App settings
- [x] Concurrency model
- [x] Shell runner
- [x] Service layer follow-through for the remaining Phase 2 infrastructure

## App Database

Use **SwiftData** for the app's own persistent models. It provides `@Model` macros, automatic migrations, SwiftUI integration via `@Query`, and iCloud sync potential.

### SwiftData Models

```swift
@Model
class Project {  // Skep/Data/Project.swift
    @Attribute(.unique) var path: String
    var name: String
    var gitRemote: String?
    /// Preferred git remote name paired with `gitRemote` and `baseRef`. Nil for local-only repos.
    var remoteName: String?
    var gitBranch: String?
    var baseRef: String?
    var githubRepository: String?  // "owner/repo"
    var githubConnected: Bool = false
    @Relationship(deleteRule: .cascade) var threads: [AgentThread] = []
}

@Model
class AgentThread {  // Skep/Data/AgentThread.swift
    var name: String
    var branch: String?
    var pendingCleanupBranches: [String] = []
    var worktreePath: String?
    /// Persisted first-run marker for restore/relaunch correctness.
    var hasCompletedInitialSetup: Bool = false
    var permissionMode: String = "default"  // "default", "plan", "acceptEdits", "auto", "bypassPermissions" (UI-exposed modes only; "dontAsk" is a CI-only mode excluded from the dropdown)
    var effort: String = "medium"           // "low", "medium", "high", "max" (from AppSettings default)
    var useWorktree: Bool = false          // Mirrors AppSettings.createWorktreeByDefault for fresh threads
    var archivedAt: Date?
    var project: Project?
    @Relationship(deleteRule: .cascade) var conversations: [Conversation] = []
}

@Model
class Conversation {  // Skep/Data/Conversation.swift
    @Attribute(.unique) var id: String = UUID().uuidString  // Stable string ID used as key in AgentsManager
    var title: String?
    var provider: String?
    var isActive: Bool = true
    var isMain: Bool = true
    var displayOrder: Int = 0
    var thread: AgentThread?
    @Relationship(deleteRule: .cascade) var events: [ConversationEventRecord] = []
}

@Model
class ConversationEventRecord {  // Skep/Data/ConversationEventRecord.swift
    // #Index: filter by conversationId, sort by timestamp (freestanding macro, not an @attribute).
    #Index<ConversationEventRecord>([\.conversationId, \.timestamp])
    @Attribute(.unique) var id: String = UUID().uuidString  // Stable string ID for use as ChatItem key
    /// Denormalized for fast @Query filtering — avoids slow relationship joins.
    var conversationId: String = ""
    var type: String          // "message", "tool_call", "tool_result", "thinking", "tokens", "notification", "stop", "session_init", "error"
    var role: String?         // "user", "assistant" (for messages)
    var content: String?      // Message text, thinking text, error message
    var toolId: String?       // For tool calls/results
    var toolName: String?     // e.g. "Bash", "Edit", "Read", "Agent"
    var toolInput: String?    // JSON string of tool arguments
    var toolOutput: String?   // Tool stdout / primary tool result text
    var toolOutputStderr: String?   // Structured stderr from tool_use_result
    var toolOutputInterrupted: Bool = false   // tool_use_result.interrupted
    var toolOutputIsImage: Bool = false       // tool_use_result.isImage
    var toolOutputNoOutputExpected: Bool = false  // tool_use_result.noOutputExpected
    var parentToolUseId: String?  // Non-nil when this event belongs to a sub-agent (points to the Agent tool_use id)
    var callerAgent: String?      // Sub-agent name from caller field (e.g. "Explore", "Plan")
    var isError: Bool = false
    var tokenInput: Int = 0
    var tokenOutput: Int = 0
    var tokenCacheRead: Int = 0
    var durationMs: Int = 0        // Wall-clock turn duration from result event
    var costUsd: Double = 0        // Turn cost from result event's total_cost_usd
    var notificationType: String?  // e.g. "idle_prompt", "permission_prompt"
    var stopReason: String?        // From result event: e.g. "end_turn", "max_tokens", error description
    var timestamp: Date = Date()
    var conversation: Conversation?

    /// Convenience init with defaults — `@Model` has no memberwise init.
    init(
        type: String,
        role: String? = nil,
        content: String? = nil,
        toolId: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil,
        toolOutput: String? = nil,
        toolOutputStderr: String? = nil,
        toolOutputInterrupted: Bool = false,
        toolOutputIsImage: Bool = false,
        toolOutputNoOutputExpected: Bool = false,
        isError: Bool = false,
        tokenInput: Int = 0,
        tokenOutput: Int = 0,
        tokenCacheRead: Int = 0,
        durationMs: Int = 0,
        costUsd: Double = 0,
        notificationType: String? = nil
    ) {
        self.type = type
        self.role = role
        self.content = content
        self.toolId = toolId
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolOutput = toolOutput
        self.toolOutputStderr = toolOutputStderr
        self.toolOutputInterrupted = toolOutputInterrupted
        self.toolOutputIsImage = toolOutputIsImage
        self.toolOutputNoOutputExpected = toolOutputNoOutputExpected
        self.isError = isError
        self.tokenInput = tokenInput
        self.tokenOutput = tokenOutput
        self.tokenCacheRead = tokenCacheRead
        self.durationMs = durationMs
        self.costUsd = costUsd
        self.notificationType = notificationType
    }
}
```

Normalize persisted filesystem paths before saving them. For v1, that means storing `URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path` for `Project.path`, `AgentThread.worktreePath`, and session-map `cwd`, and using that canonicalized form consistently for uniqueness, worktree lookup, and Claude session-file path resolution.

```swift
enum CanonicalPath {  // Skep/Utilities/CanonicalPath.swift
    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}
```

Use one shared helper instead of open-coding path canonicalization at every persistence boundary. Add focused unit tests for symlinked paths, repeated normalization idempotence, and non-existent-but-valid filesystem paths.

### Key Relationships

```
┌──────────────┐     ┌──────────────────┐     ┌────────────────┐     ┌──────────────────────────┐
│   Project    │ 1:N │   AgentThread    │ 1:N │  Conversation  │ 1:N │ ConversationEventRecord   │
│──────────────│────▶│──────────────────│────▶│────────────────│────▶│──────────────────────────│
│ name         │     │ name             │     │ id             │     │ id                       │
│ path         │     │ worktreePath     │     │ title          │     │ conversationId (#Index)   │
│ gitRemote    │     │ branch           │     │ provider       │     │ type                     │
│ remoteName   │     │ permissionMode   │     │ isActive       │     │ role, content             │
│              │     │ effort           │     │                │     │ toolId, toolName          │
│              │     │ archivedAt       │     │                │     │ tokenInput, tokenOutput   │
└──────────────┘     │                  │     └────────────────┘     └──────────────────────────┘
                     └──────────────────┘
                              │
                              │ (via session map JSON, not SwiftData)
                              ▼
                     ┌──────────────────┐
                     │  SessionEntry    │
                     │──────────────────│
                     │ cwd              │
                     │ providerId       │
                     │ appSessionId     │  → next resumable provider session ID
                     │ launchSessionId  │  → live child argv ID for orphan lookup
                     └──────────────────┘
```

`Project.gitRemote` and `Project.remoteName` are a paired invariant for later phases: both are nil for local-only repositories, or both describe the same chosen remote so worktree creation, ahead-of-base checks, and GitHub integration never re-pick different remotes ad hoc.

`SessionEntry.cwd` stores the canonicalized working directory path, and Claude's on-disk session file lives under its provider-owned encoding of that canonical path rather than the raw launch string.

Conversation invariants for later phases:
- Each thread has exactly one main conversation (`isMain == true`).
- `displayOrder` is unique within a thread and new side conversations append at `max + 1`.
- User-creatable conversations in v1 should always have a concrete provider ID before first spawn, even though the field stays optional in storage for migration tolerance and partially created records.

All SwiftData relationships use cascade delete: deleting a project deletes its threads, which deletes conversations, which deletes event records.

Conversation events are **eventually** persisted from the agent JSON stream. While a `ConversationViewModel` is mounted, coalesced saves keep SwiftData close behind live output. If a conversation keeps running with no mounted VM, `EventBuffer` still preserves in-launch replay, but SwiftData may lag until a VM reconnects and drains that tail. This never restores live process state or launch-scoped UI state; only durable history survives.

### What's NOT in SwiftData

- Git commit history (fetched on-demand via `git log`)
- Worktree list (fetched via `git worktree list`)
- PR/issue lists (fetched via `gh pr list`)
- Agent session bindings (`appSessionId` / `launchSessionId` in session map JSON file, not the DB)
- App-owned access tokens (v1 delegates auth storage to external CLIs such as `gh`)
- In-flight process state (in memory only)

### Redundant Storage with Claude

Conversation events are stored in two places:
1. **Claude's session file** (`~/.claude/projects/<encoded-cwd>/<uuid>.jsonl`) -- maintained by Claude for `--resume`, where `<encoded-cwd>` is Claude's provider-owned encoding of the canonicalized working directory path.
2. **Skep's SwiftData database** (`ConversationEventRecord` rows) -- for the chat UI.

This duplication is intentional: Claude's `.jsonl` is undocumented and not query-friendly, while Skep needs reactive `@Query` history for the UI.

**Drift risk**: a crash, or a background conversation that outlives its mounted VM and then app shutdown, can leave Claude's session file ahead of Skep's database. `--resume` still restores provider context, but the chat UI may miss those late events until the conversation continues again. That UI lag is an acceptable v1 tradeoff.

---

## State Management

### View Model Architecture

Each pane and screen has its own `@Observable` view model. They stay scoped to a UI region and communicate through SwiftData plus shared services.

```
AppState (global: pane visibility, selected sidebar item, one-shot UI intents)
  ├── SidebarViewModel (projects, threads, status indicators)
  ├── ConversationViewModel (per conversation: agent stream subscription, eventual SwiftData catch-up for durable history)
  │     └── reads ConversationState via ConversationRuntimeStore (implemented by DefaultAgentsManager)
  ├── DiffViewerViewModel (file changes, staging, contextual action, PR discovery)
  ├── SkillsViewModel (catalog, installed, search)
  ├── MCPViewModel (servers, providers)
  └── SettingsViewModel (read/write app settings)
```

**How they're connected**: view models don't reference each other directly. They share state through:
1. **SwiftData** -- one view model writes, another reads via `@Query`.
2. **Knit services** -- shared injectable services like `AgentsManager`, `GitService`, `SessionManager`.
3. **NotificationCenter** -- for cross-cutting invalidation (e.g. `.agentStatusChanged` lets `DiffViewerViewModel` re-check active conversation statuses and refresh repo state after a turn settles without coupling the diff pane directly to chat view models).

### ModelContext Boundaries

`ModelContext` is registered as **transient** in Knit, so each resolve can produce a different write context even though all of them share the same `ModelContainer`. The hard rule is: **never attach or mutate a SwiftData `@Model` from one context through another context**.

Apply that rule consistently:

1. **SwiftUI views** that already render models from the environment should use the environment `modelContext` for view-local identity resolution and any small UI-owned writes.
2. **Injected `@MainActor` view models** may store their own transient `ModelContext`, but only for UI-owned persistence work. They must still treat incoming `Project`, `AgentThread`, and `Conversation` objects as identity carriers only. Before mutating relationships or inserting linked records, they re-resolve the same model inside their own context via `persistentModelID` or a unique key such as `Project.path`.
3. **`.container` services and actors must not store `ModelContext`**. If a background or singleton layer needs SwiftData work, hop to a main-actor helper/repository for that operation and resolve fresh model instances inside that operation's context.
4. **Cross-layer handoff** should prefer stable identity over raw `@Model` instances. If a helper returns a model created in its private context, callers resolve that model again in their own read context before storing it in long-lived UI state. The one deliberate exception is `AppState.selectedSidebarItem`: it stays entirely inside the window-composition layer and may hold models already resolved in the SwiftUI environment context, but those models must still be re-resolved before being passed into injected services or view models with their own transient `ModelContext`.

### AppState (Global)

Although the views that consume it do not land until Phase 6, define `AppState` and `SidebarItem` in Phase 2. They are pure launch-scoped state types with no view dependencies, and building them early keeps later sidebar/layout/chat wiring pointed at one shared owner instead of introducing temporary per-screen selection placeholders.

```swift
@MainActor @Observable
class AppState {  // Skep/App/AppState.swift
    /// Launch-scoped navigation selection.
    var selectedSidebarItem: SidebarItem?
    /// Launch-scoped chrome state.
    var isRightPaneVisible: Bool = false
    var isLeftPaneVisible: Bool = true
    /// One-shot menu and shortcut requests.
    var pendingCommand: CommandRequest?
    /// One-shot diff action routed to the active `ConversationView`.
    var pendingDiffAction: DiffActionRequest?
    /// Launch-scoped last-opened conversation per thread.
    var selectedConversationIDs: [PersistentIdentifier: PersistentIdentifier] = [:]
    /// Bookmark restored when dismissing Settings.
    var previousSelection: SidebarBookmark?

    func openSettings() {
        if selectedSidebarItem != .settings {
            previousSelection = selectedSidebarItem.flatMap(SidebarBookmark.init)
        }
        selectedSidebarItem = .settings
    }

    func startNewThreadFlow() {
        pendingCommand = .newThread(UUID())
    }

    func openNewProjectFlow() {
        pendingCommand = .newProject(UUID())
    }

    func requestDiffAction(message: String, conversationID: PersistentIdentifier) {
        pendingDiffAction = DiffActionRequest(
            id: UUID(),
            conversationID: conversationID,
            message: message
        )
    }

    /// Pure read. Healing happens in `repairSelectedConversationIfNeeded(for:)`.
    func selectedConversation(in thread: AgentThread) -> Conversation? {
        let sorted = thread.conversations.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.isMain && !$1.isMain
            }
            return $0.displayOrder < $1.displayOrder
        }
        if let selectedId = selectedConversationIDs[thread.persistentModelID],
           let selected = sorted.first(where: { $0.persistentModelID == selectedId }) {
            return selected
        }
        return sorted.first(where: { $0.isMain }) ?? sorted.first
    }

    func repairSelectedConversationIfNeeded(for thread: AgentThread) {
        let key = thread.persistentModelID
        let resolvedID = selectedConversation(in: thread)?.persistentModelID
        if let resolvedID {
            if selectedConversationIDs[key] != resolvedID {
                selectedConversationIDs[key] = resolvedID
            }
        } else {
            selectedConversationIDs.removeValue(forKey: key)
        }
    }

    func selectConversation(_ conversation: Conversation, in thread: AgentThread) {
        if pendingDiffAction?.conversationID != conversation.persistentModelID {
            pendingDiffAction = nil
        }
        selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
    }

    /// Identifier-based bookmark, resolved via SwiftData on dismiss.
    enum SidebarBookmark: Hashable {
        case skills
        case mcp
        case projectPath(String)            // Project.path (unique, stable)
        case threadId(PersistentIdentifier)  // AgentThread.persistentModelID

        init?(_ item: SidebarItem) {
            switch item {
            case .skills: self = .skills
            case .mcp: self = .mcp
            case .settings: return nil
            case .project(let p): self = .projectPath(p.path)
            case .thread(let t): self = .threadId(t.persistentModelID)
            }
        }
    }

    enum CommandRequest: Equatable {
        case newThread(UUID)
        case newProject(UUID)

        var id: UUID {
            switch self {
            case .newThread(let id), .newProject(let id): return id
            }
        }
    }

    struct DiffActionRequest: Equatable {
        let id: UUID
        let conversationID: PersistentIdentifier
        let message: String
    }
}

`pendingDiffAction` is a one-shot UI intent, not a durable queue. A new request replaces any older unconsumed one, and navigation away from the target conversation cancels it instead of replaying it later. Because this handoff crosses layout/chat boundaries, it stores only the target conversation's `PersistentIdentifier`, never a raw `Conversation` model.

enum SidebarItem: Hashable {  // Skep/App/AppState.swift
    case skills
    case mcp
    case project(Project)
    case thread(AgentThread)
    case settings

    // @Model classes aren't Hashable; use stable id/path properties.
    func hash(into hasher: inout Hasher) {
        switch self {
        case .skills: hasher.combine("skills")
        case .mcp: hasher.combine("mcp")
        case .settings: hasher.combine("settings")
        case .project(let p): hasher.combine(p.path)
        case .thread(let t): hasher.combine(t.persistentModelID)
        }
    }

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        switch (lhs, rhs) {
        case (.skills, .skills), (.mcp, .mcp), (.settings, .settings): return true
        case (.project(let a), .project(let b)): return a.path == b.path
        case (.thread(let a), .thread(let b)): return a.persistentModelID == b.persistentModelID
        default: return false
        }
    }
}
```

**Unit tests for AppState** (use an in-memory SwiftData container when a test needs real `persistentModelID` values):
- `openSettings()` saves `previousSelection` only when leaving a non-settings route; reopening Settings does not overwrite the preserved bookmark
- `selectedConversation(in:)` is pure and does **not** mutate `selectedConversationIDs` during render-time reads
- `repairSelectedConversationIfNeeded(for:)` heals a stale stored conversation ID by falling back to the main conversation, then the first by `displayOrder`
- `repairSelectedConversationIfNeeded(for:)` removes the stored bookmark when the thread has no conversations
- `selectConversation(_:in:)` clears `pendingDiffAction` only when the selected conversation changes away from the targeted conversation
- `requestDiffAction(message:conversationID:)` replaces any older request with a fresh UUID even when the message text is identical

### How View Models Are Created

View models are created by their owning view. Most are scoped to `ContentView`'s lifetime (effectively the app session). `ConversationViewModel` is the exception — it's created per-conversation-view, but its mutable state (`TurnState`, `MessageQueue`, streaming text) lives in the shared runtime `ConversationState` owned by `AgentsManager` so it survives VM destruction during navigation.

The full `SkepApp` entry point and `ContentView` wiring code is built last, after all view models and services exist.

---

## App Settings

Settings are stored in `UserDefaults` and loaded into memory on startup. `AppSettings` is `Codable`, so it's serialized as a single JSON blob under one `UserDefaults` key. The key requirement is that settings changes are observable so all parts of the app react in real time.

### SettingsService Protocol

```swift
/// @MainActor because concrete implementations use @Observable (Swift 6 strict concurrency
/// requires matching isolation). Off-main-actor consumers access `current` via `await`;
/// the returned struct copy is safe to use after the hop.
@MainActor
protocol SettingsService {  // Skep/Services/Settings/SettingsService.swift
    var current: AppSettings { get }
    func update(_ transform: (inout AppSettings) -> Void)
}

struct AppSettings: Codable, Sendable {  // Skep/Services/Settings/AppSettings.swift
    var defaultProvider: String = "claude"
    var permissionMode: String = "default"
    var effort: String = "medium"            // "low", "medium", "high", "max"
    var autoGenerateNames: Bool = true
    var autoTrustWorktrees: Bool = true
    var createWorktreeByDefault: Bool = false
    var theme: String = "system"             // "light", "dark", "system"
    var codeFontFamily: String = "SF Mono"
    var codeFontSize: Int = 13
    var chatFontSize: Int = 14
    var notifications: NotificationSettings = NotificationSettings()
    var branchPrefix: String = "skep"
    var pushOnCreate: Bool = false
    var providerConfigs: [String: ProviderCustomConfig] = [:]

    func normalized() -> AppSettings {
        var copy = self
        if copy.defaultProvider != "claude" {
            copy.defaultProvider = "claude"
        }
        if !["default", "plan", "acceptEdits", "auto", "bypassPermissions"].contains(copy.permissionMode) {
            copy.permissionMode = "default"
        }
        if !["low", "medium", "high", "max"].contains(copy.effort) {
            copy.effort = "medium"
        }
        if !["light", "dark", "system"].contains(copy.theme) {
            copy.theme = "system"
        }
        if let soundName = copy.notifications.soundName,
           !["Glass", "Pop", "Tink", "Purr"].contains(soundName) {
            copy.notifications.soundName = "Glass"
        }
        return copy
    }
}

struct ProviderCustomConfig: Codable, Sendable {  // Skep/Services/Settings/AppSettings.swift
    var cli: String?              // Custom CLI path or command
    var resumeFlag: String?       // Override resume flag
    var defaultArgs: String?      // Override default args
    var autoApproveFlag: String?  // Override auto-approve flag
    var initialPromptFlag: String? // Override prompt flag
    var extraArgs: String?        // Additional args appended to every invocation; supports shell-style quoting for grouped values, but not expansion/globbing
    var env: [String: String]?    // Additional env vars for this provider
}

struct NotificationSettings: Codable, Sendable {  // Skep/Services/Settings/AppSettings.swift
    var enabled: Bool = true
    var osNotifications: Bool = true
    var sound: Bool = true
    var soundName: String? = "Glass"  // Nil is tolerated on decode; UI/runtime fall back to Glass.
}
```

Keep the persisted representation tolerant, but normalize unknown values when loading or applying settings: invalid `defaultProvider` falls back to `"claude"` in v1, invalid `permissionMode` falls back to `"default"`, invalid `effort` falls back to `"medium"`, invalid `theme` falls back to `"system"`, and invalid notification `soundName` falls back to `"Glass"`. Do not pass unchecked persisted strings through to CLI argument builders or fixed-option UI pickers. When a second provider ships, revisit this normalization alongside the provider-picker work so the fallback is driven by real provider metadata instead of a hardcoded Claude-first default.

### SkepProjectConfig (Shared `.skep.json` Parser)

Parsed representation of the per-project `.skep.json` config file. Shared by `DefaultWorktreeManager` (for setup/teardown scripts and file preservation during worktree creation) and the project creation flow (for detecting project configuration). Defined here so it's available before either consumer.

```swift
/// Per-project `.skep.json` config. Immutable after init; missing/malformed → all fields nil.
struct SkepProjectConfig {  // Skep/Services/Settings/SkepProjectConfig.swift
    let setupScript: String?
    let setupTimeoutSeconds: Int?
    let teardownScript: String?
    let shellSetup: String?
    let preservePatterns: [String]?
    let actions: [ProjectAction]?

    struct ProjectAction {
        let name: String
        let command: String
    }

    init(projectPath: String) {
        let configURL = URL(fileURLWithPath: projectPath).appendingPathComponent(".skep.json")
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            self.setupScript = nil
            self.setupTimeoutSeconds = nil
            self.teardownScript = nil
            self.shellSetup = nil
            self.preservePatterns = nil
            self.actions = nil
            return
        }
        let scripts = json["scripts"] as? [String: Any]
        self.setupScript = (scripts?["setup"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.setupTimeoutSeconds = (scripts?["setupTimeoutSeconds"] as? Int)
            .flatMap { $0 > 0 ? $0 : nil }
        self.teardownScript = (scripts?["teardown"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.shellSetup = (json["shellSetup"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.preservePatterns = json["preservePatterns"] as? [String]
        self.actions = (json["actions"] as? [[String: Any]])?.compactMap { action in
            guard let name = action["name"] as? String,
                  let command = action["command"] as? String
            else { return nil }
            return ProjectAction(name: name, command: command)
        }
    }
}
```

**Unit tests for SkepProjectConfig** (use a temp directory with a `.skep.json` file): cover all fields (setup, teardown, shellSetup, preservePatterns, actions) and missing/malformed file cases. Non-obvious:
- Empty string values for scripts are treated as nil (not empty string)
- `scripts.setupTimeoutSeconds` ignores zero/negative values (falls back to default timeout)
- Missing keys return nil (partial config is valid — not all fields required)

### Concrete Implementations

```swift
@MainActor @Observable
class UserDefaultsSettingsService: SettingsService {  // Skep/Services/Settings/UserDefaultsSettingsService.swift
    private static let key = "appSettings"
    private let defaults: UserDefaults
    private(set) var current: AppSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.current = decoded.normalized()
        } else {
            self.current = AppSettings()
        }
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&current)
        current = current.normalized()
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// Test mock — in-memory only, no persistence.
@MainActor @Observable
class InMemorySettingsService: SettingsService {  // SkepTests/Services/InMemorySettingsService.swift
    private(set) var current = AppSettings()

    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&current)
        current = current.normalized()
    }
}
```

`@MainActor` because `current` is read by SwiftUI views and `@Observable` view models on the main actor. `@Observable` so that changes to `current` trigger SwiftUI re-renders automatically.

**Unit tests for SettingsService** (use `UserDefaultsSettingsService` with a custom suite, or `InMemorySettingsService`): cover `current` defaults, `update()` mutations, and persistence round-trips. Non-obvious:
- `UserDefaultsSettingsService`: round-trip test — `update()` then re-create the service and verify `current` reflects the change
- `UserDefaultsSettingsService`: falls back to defaults when stored JSON is corrupt
- `UserDefaultsSettingsService`: invalid stored `defaultProvider` / `permissionMode` / `effort` / `theme` / notification `soundName` values are normalized on load before any caller reads `current`
- `InMemorySettingsService` and `UserDefaultsSettingsService` both normalize invalid values during `update()` so unchecked strings cannot linger in memory until the next app launch

### Settings UI, Application, and SettingsViewModel

The settings screen layout, how each setting is applied, and `SettingsViewModel` are in [Part 1c: Settings UI](part1c-settings-ui.md).

---

## Concurrency Model

Use Swift concurrency throughout, but be explicit about ownership. `async`/`await` call trees are preferred when a parent already owns the work; standalone `Task` handles are reserved for operations whose lifetime must outlive the current synchronous scope.

### @MainActor for UI State

All `@Observable` view models and SwiftUI-facing state should be `@MainActor`:

```swift
@MainActor @Observable
class SomeViewModel {
    var items: [String] = []
    var isLoading: Bool = false

    func load() async { ... }
}
```

### Background Tasks

Unstructured tasks are allowed, but each one must have an owner, a stored handle when it can outlive the current method, and an explicit cancellation point during teardown:

- **Provider detection**: `Task { await providerDetection.checkAllProviders() }`
- **Git operations**: `Task { let status = await gitService.status(path:) }`
- **Worktree creation**: `Task { try await worktreeManager.create(projectPath:threadName:baseRef:remoteName:) }`

Protocols stored by actors or crossing concurrency domains should conform to `Sendable`. UI-facing services that intentionally stay on the main actor (`SettingsService`, later `NotificationManager`) should be `@MainActor` instead. `ModelContext` stays main-actor-only.

### Agent Event Stream

The stdout JSON reader runs in an owned task tied to the agent process lifetime. Prefer `Task {}` plus a stored handle over `Task.detached` unless the implementation intentionally needs to drop actor inheritance and task-local values. `DefaultAgentsManager` owns/cancels the reader task, and `ConversationViewModel` owns/cancels its stream-subscription task. Events are delivered via `AsyncStream<ConversationEvent>` — the `ConversationViewModel` subscribes to this stream and persists events to SwiftData on the main actor.

---

## Shell Runner (Shared Helper)

The boilerplate for spawning a process, piping stdout/stderr, waiting, and checking the exit status is shared across `GitService`, `GitHubService`, and `ProviderDetectionService`. Extract it into a reusable `ShellRunner`.

`ShellRunner` does not perform PATH lookup or shell parsing. Callers pass either an absolute/pre-resolved executable path, or explicitly run a shell themselves (for example `/bin/zsh` with `-lc`) when they need shell syntax.

```swift
struct ShellResult: Sendable {  // Skep/Services/Shell/ShellRunner.swift
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let stdoutWasTruncated: Bool
    let stderrWasTruncated: Bool
    var succeeded: Bool { exitCode == 0 }
}

protocol ShellRunner: Sendable {  // Skep/Services/Shell/ShellRunner.swift
    func run(executable: String, args: [String], in directory: String?, environment: [String: String]?, timeout: Duration?, stdoutLimitBytes: Int?, stderrLimitBytes: Int?) async throws -> ShellResult  // defaults via extension
}

extension ShellRunner {
    func run(
        executable: String,
        args: [String],
        in directory: String? = nil,
        environment: [String: String]? = nil,
        timeout: Duration? = nil,
        stdoutLimitBytes: Int? = nil,
        stderrLimitBytes: Int? = nil
    ) async throws -> ShellResult {
        try await run(
            executable: executable,
            args: args,
            in: directory,
            environment: environment,
            timeout: timeout,
            stdoutLimitBytes: stdoutLimitBytes,
            stderrLimitBytes: stderrLimitBytes
        )
    }
}

final class DefaultShellRunner: ShellRunner, @unchecked Sendable {  // Skep/Services/Shell/DefaultShellRunner.swift
    func run(
        executable: String,
        args: [String],
        in directory: String?,
        environment: [String: String]? = nil,
        timeout: Duration? = nil,
        stdoutLimitBytes: Int? = nil,
        stderrLimitBytes: Int? = nil
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // The process object is exclusively owned by this run call.
        nonisolated(unsafe) let unsafeProcess = process

        return try await withTaskCancellationHandler {
            try process.run()

            async let stdoutCapture = readBoundedOutput(
                from: stdoutPipe.fileHandleForReading,
                maxBytes: stdoutLimitBytes
            )
            async let stderrCapture = readBoundedOutput(
                from: stderrPipe.fileHandleForReading,
                maxBytes: stderrLimitBytes
            )

            if let timeout {
                let resumed = OSAllocatedUnfairLock(initialState: false)
                let didFinish = await withCheckedContinuation { continuation in
                    process.terminationHandler = { _ in
                        if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                            continuation.resume(returning: true)
                        }
                    }
                    // Fast-exit guard: the child may have already finished between
                    // `run()` and handler installation.
                    if !process.isRunning,
                       resumed.withLock({ let old = $0; $0 = true; return !old }) {
                        continuation.resume(returning: true)
                    }
                    Task {
                        try? await Task.sleep(for: timeout)
                        if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                            process.terminate()
                            continuation.resume(returning: false)
                        }
                    }
                }
                if !didFinish {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                    _ = await stdoutCapture
                    _ = await stderrCapture
                    throw ShellError.timeout(executable: executable, timeout: timeout)
                }
            } else {
                await withCheckedContinuation { continuation in
                    let resumed = OSAllocatedUnfairLock(initialState: false)
                    process.terminationHandler = { _ in
                        if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                            continuation.resume()
                        }
                    }
                    // Fast-exit guard for very short-lived commands.
                    if !process.isRunning,
                       resumed.withLock({ let old = $0; $0 = true; return !old }) {
                        continuation.resume()
                    }
                }
            }

            let (stdout, stdoutWasTruncated) = await stdoutCapture
            let (stderr, stderrWasTruncated) = await stderrCapture

            return ShellResult(
                stdout: String(data: stdout, encoding: .utf8) ?? "",
                stderr: String(data: stderr, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus,
                stdoutWasTruncated: stdoutWasTruncated,
                stderrWasTruncated: stderrWasTruncated
            )
        } onCancel: {
            guard unsafeProcess.isRunning else { return }
            unsafeProcess.terminate()
            // Cancellation should reap the child, not leave a SIGTERM-ignoring process behind.
            Task.detached {
                try? await Task.sleep(for: .seconds(2))
                if unsafeProcess.isRunning {
                    kill(unsafeProcess.processIdentifier, SIGKILL)
                }
            }
        }
    }

    private func readBoundedOutput(from handle: FileHandle, maxBytes: Int?) async -> (Data, Bool) {
        // Read in chunks, cap retained bytes, keep draining after truncation.
        ...
    }
}

enum ShellError: Error, Sendable {  // Skep/Services/Shell/ShellRunner.swift
    case timeout(executable: String, timeout: Duration)
}
```

```swift
// Inside CLIGitService
func status(in directory: String) async throws -> [FileStatus] {
    let result = try await shell.run(
        executable: "/usr/bin/git",
        args: ["--no-optional-locks", "status", "--porcelain=v2", "-z", "--no-ahead-behind"],
        in: directory
    )
    guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
    return parseStatus(result.stdout)
}
```

`ShellRunner` is injectable via Knit. Tests use `MockShellRunner`. The optional `environment` overlay lets worktree lifecycle scripts add deterministic `SKEP_*` variables without rebuilding the inherited environment by hand.

`DefaultShellRunner` still needs focused integration coverage for deadlock, timeout, and cancellation behavior. Verify: large stdout+stderr drains do not deadlock, timeout terminates the child, caller cancellation terminates and reaps the child (including the SIGKILL fallback path), environment overlays merge correctly, and non-zero exit captures stderr + exit code.

---


## Service Layer Architecture

Define data-layer and infrastructure concerns as **protocols** resolved via Knit.

This table is a forward-reference wiring plan for Parts 2-4. Define each service in its own section later and register assemblies as you reach them.

Key injectable services:

| Protocol | Responsibility | Concrete | Mock | Scope |
|---|---|---|---|---|
| `ModelContainer` | SwiftData persistence container | Framework type | In-memory config | `.container` (singleton) |
| `ModelContext` | SwiftData read/write context | Framework type | In-memory context | `.transient` (per resolve) |
| `ShellRunner` | Process spawning helper | `DefaultShellRunner` | `MockShellRunner` | `.container` (singleton) |
| `GitService` | Git CLI operations | `CLIGitService` | `MockGitService` | `.container` (singleton) |
| `WorktreeManager` | Worktree create/remove/list | `DefaultWorktreeManager` | `MockWorktreeManager` | `.container` (singleton) |
| `GitHubCLIService` | `gh` CLI lifecycle (install check, auth, command execution) (`@MainActor`) | `DefaultGitHubCLIService` | `MockGitHubCLIService` | `.container` (singleton) |
| `GitHubService` | `gh` CLI operations (PRs, issues, CI) | `CLIGitHubService` | `MockGitHubService` | `.container` (singleton) |
| `SessionManager` | Session map, UUID generation, resume args | `DefaultSessionManager` | `InMemorySessionManager` | `.container` (singleton) |
| `AgentsManager` | Spawn/kill/track agent processes | `DefaultAgentsManager` | `MockAgentsManager` | `.container` (singleton) |
| `ConversationRuntimeStore` | Shared per-conversation launch-scoped runtime state lookup | `DefaultAgentsManager` | `MockConversationRuntimeStore` or `MockAgentsManager` | `.container` (same shared instance as `AgentsManager`) |
| `AgentAdapter` | Provider-specific CLI args, JSON decoding | `ClaudeAdapter` | `MockAgentAdapter` | N/A — created inline by `DefaultAgentsManager.resolveAdapter()` |
| `FileListManager` | Cached file listing for @-mention | `GitFileListManager` | `MockFileListManager` | `.container` (singleton) |
| `SkillsService` | Install/uninstall/sync skills | `DefaultSkillsService` | `MockSkillsService` | `.container` (singleton) |
| `MCPService` | Read/write MCP configs | `DefaultMCPService` | `MockMCPService` | `.container` (singleton) |
| `SettingsService` | App settings persistence | `UserDefaultsSettingsService` | `InMemorySettingsService` | `.container` (singleton) |
| `AgentRegistry` | Shared agent metadata (install/docs, skills path, MCP config, provider projection source) | `DefaultAgentRegistry` | `MockAgentRegistry` | `.container` (singleton) |
| `ProviderDetectionService` | CLI detection, path resolution | `DefaultProviderDetectionService` | `MockProviderDetectionService` | `.container` (singleton) |
| `ProviderRegistry` | Provider metadata registry | `DefaultProviderRegistry` | `MockProviderRegistry` | `.container` (singleton) |
| `AgentEnvironmentBuilder` | Agent process environment | `DefaultAgentEnvironmentBuilder` | `MockAgentEnvironmentBuilder` | `.container` (singleton) |
| `NotificationManager` | OS and in-app notifications (`@MainActor`) | `DefaultNotificationManager` | `MockNotificationManager` | `.container` (singleton) |
| `ClaudeConfigStore` | Serialized read/merge/write access to Claude-owned config files (`~/.claude.json`, `.claude/settings.local.json`) | `DefaultClaudeConfigStore` | `MockClaudeConfigStore` | `.container` (singleton) |
| `ProviderSetupService` | Provider-specific pre-spawn setup (config files, trust entries) | `DefaultProviderSetupService` | `MockProviderSetupService` | `.container` (singleton) |

All services use Knit's `.container` scope because they hold shared state such as caches, processes, or file handles. View models are created by their owning views, not resolved from Knit.

For strict concurrency, any protocol stored by an actor or crossing concurrency domains should declare `Sendable` in its own part unless it is intentionally `@MainActor`-isolated. Keep that rule consistent as later service protocols are introduced.

Each service gets its own Knit `ModuleAssembly`. The documented v1 build only generates Knit resolver extensions, so do not assume generated resolver tests exist. Use ordinary unit tests and startup-level DI smoke coverage to catch missing wiring unless the project later adds explicit Knit test outputs.

---
