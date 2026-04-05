# Part 1c: Settings UI

Settings screen layout, SettingsViewModel, and how each setting is applied across the app. The `SettingsService` protocol, `AppSettings` struct, `SkepProjectConfig`, and concrete implementations are in [Part 1b](part1b-data-and-services.md). Continues from Part 1b.

## How Settings Are Accessed in the UI

Phase split: **Phase 2** builds the settings types, option lists, and `SettingsViewModel` contract. The actual `SettingsScreen`, Cmd+, menu wiring, middle-pane presentation, and snapshot coverage land in **Phase 6** once the app layout exists.

Settings should be accessible via a keyboard shortcut (Cmd+,) and from the app's menu. The settings screen replaces the middle pane content when opened (dismiss via X button in top-right). Left side has a vertical tab list; right side shows the selected tab's form.

```
┌─ Settings ──────────────────────────────── ✕ ─┐
│                                                │
│  ┌──────────────┐  General                     │
│  │ General    ◀ │  Manage thread defaults       │
│  │ Agents      │  and notification settings.   │
│  │ Repository  │  ─────────────────────────    │
│  │ Interface   │                               │
│  │             │  Auto-generate thread names   │
│  │             │  Suggests a name from the  ◉  │
│  │             │  first message.                │
│  │             │                               │
│  │             │  Default provider              │
│  │             │  New threads use         Claude ▾│
│  │             │  the selected agent.           │
│  │             │                               │
│  │             │  Default permission mode       │
│  │             │  New threads start in   Default ▾│
│  │             │  the selected mode.            │
│  │             │                               │
│  │             │  Default effort                │
│  │             │  New threads start at     Medium ▾│
│  │             │  the selected level.           │
│  │             │                               │
│  │             │  Create worktree by default    │
│  │             │  New threads start on the   ◉  │
│  │             │  current branch when off.      │
│  │             │                               │
│  │             │  Auto-trust worktrees          │
│  │             │  Skip the folder trust      ◉  │
│  │             │  prompt in Claude Code.        │
│  │             │                               │
│  │             │  Notifications                 │
│  │             │  Get notified when agents   ◉  │
│  │             │  need your attention.          │
│  │             │                               │
│  │             │    Sound                       │
│  │             │    Play audio cues for      ◉  │
│  │             │    agent events.               │
│  └──────────────┘                               │
└────────────────────────────────────────────────┘
```

Each setting row has a **label** (bold), **description** (muted), and a **toggle** or **picker** on the right. V1 tabs: General (thread defaults + notifications), Agents (per-provider config overrides), Repository (branch prefix, push on create), Interface (theme, fonts).

GitHub connection remains in project settings and PR flows for v1 rather than a separate Settings tab. An Account tab is deferred until the plan defines app-owned account state beyond external CLI auth.

---

## Agent Settings and How They're Applied

**Default provider** -- which agent CLI to use for new threads.
- Read when creating a new thread. In v1 this seeds the initial main conversation's provider because Claude is the only shipped provider, so there is no separate visible provider picker yet.
- When additional providers are added, this becomes the pre-selected value in the thread-creation UI and users can override it per thread.

**Default permission mode** -- the starting `permissionMode` for new threads.
- Read at thread creation time. Seeds `AgentThread.permissionMode` from `AppSettings.permissionMode`.
- At agent spawn, the thread's stored `permissionMode` is only passed through when the active provider exposes a permission-mode flag. Providers without that capability ignore the stored value and the Phase 6 UI hides or disables the picker for that provider.
- Choosing `bypassPermissions` here is the equivalent of making new threads auto-approve by default.

**Default effort** -- the starting `effort` level for new threads on providers that support effort controls.
- Read at thread creation time. Seeds `AgentThread.effort` from `AppSettings.effort`.
- At agent spawn, the thread's stored `effort` is passed through as `--effort <level>` when the provider exposes an effort flag.
- Existing threads keep their own persisted `AgentThread.effort`; changing the global default only affects newly created threads.

**Auto-generate thread names** -- enable/disable auto-naming from the first user message.
- Read when the first message is sent. If disabled, the thread keeps its default name.

**Auto-trust worktrees** -- for Claude, auto-write trust entries to `~/.claude.json`.
- Read at agent spawn time. If enabled, the provider is Claude, and the thread is actually launching from a worktree-backed directory, the trust entry is written before spawning.

**Create worktree by default** -- whether new threads get isolated worktrees.
- Read in the thread creation UI. Pre-checks the "use worktree" toggle.

**Provider custom configs** -- per-provider CLI overrides (`ProviderCustomConfig` in `Skep/Services/Settings/AppSettings.swift`).
- Read at agent spawn time by `resolveProviderCommandConfig()`. Custom CLI path, extra args, and env vars are merged with registry defaults.

---

## Appearance Settings and How They're Applied

**Theme** -- light, dark, or system (default). Controls the Liquid Glass material appearance and all color tokens throughout the app. Use SwiftUI's `preferredColorScheme` modifier:
- `system` → no override, follows macOS system setting
- `light` → `.preferredColorScheme(.light)`
- `dark` → `.preferredColorScheme(.dark)`

Liquid Glass materials automatically adapt to the active color scheme.

**Code font family and size** -- used for code blocks in assistant messages and the diff viewer. Applied via the syntax highlighter's configuration.

**Chat font size** -- controls the base font size for the chat interface. Applied as a SwiftUI environment value.

---

## Notification Settings and How They're Applied

**Enabled** -- master toggle. Checked in the event stream handler before showing any notification.

**OS notifications** -- checked after the master toggle. If disabled, agent state events are still received and broadcast to the UI (for in-app indicators) but no `UNUserNotificationCenter` notification is posted.

**Sound** -- whether to play a sound when the agent needs attention. Two contexts:
- **App unfocused**: controlled by the `sound` property on `UNNotificationContent`. In v1, this uses `UNNotificationSound.default` when enabled. `UNNotificationSound` only supports bundled or app-container sound files, so arbitrary `/System/Library/Sounds/` selections do not carry over to OS notifications.
- **App focused**: play a subtle in-app chime via `NSSound(named: "Glass")?.play()` when a turn completes or the agent needs input. Uses built-in macOS system sounds (no bundled assets needed). Other good options: "Pop", "Tink", "Purr". The user-selected `soundName` applies here.

When `sound` is enabled, the General tab shows a secondary picker for the in-app chime (`Glass`, `Pop`, `Tink`, `Purr`). That picker does not affect the OS-notification path, which stays on `UNNotificationSound.default`. Unknown persisted sound names are normalized away before the UI reads them, and the picker-facing `SettingsViewModel.soundName` must always resolve to one of these four labels so the control never lands in an out-of-range state.

**Focus detection**: use `NSApp.isActive` to determine whether the app is frontmost. This drives the notification/sound routing.

UI behavior for the General tab:
- `notificationsEnabled == false` disables the subordinate OS-notification and sound rows without clearing their stored values.
- `soundEnabled == false` hides or disables the secondary sound-name picker, again preserving the last chosen value so re-enabling sound restores the prior selection.

The focus detection and notification routing logic lives in `DefaultNotificationManager` (see [Part 1e](part1e-events.md)).

The universal event model (`ConversationEvent`, `AgentConfig`, `AgentSpawnConfig`, `AgentError`) and `NotificationManager` are in [Part 1e: Events and Notifications](part1e-events.md).

---

## Repository Settings and How They're Applied

**Branch prefix** -- prefix for worktree branch names (e.g. `skep`).
- Read by worktree creation. The branch name starts as `{prefix}/{slugified-name}-{hash}` and appends `-2`, `-3`, etc. only when an identical-name thread would otherwise collide with an existing branch/worktree.

**Push on create** -- auto-push worktree branches to remote on creation.
- Read by worktree creation. If enabled, `git push --set-upstream origin <branch>` runs after `git worktree add`.

---

## SettingsViewModel

```swift
@MainActor @Observable
class SettingsViewModel {  // Skep/ViewModels/SettingsViewModel.swift
    private let settingsService: SettingsService

    /// Stable option sources for Phase 6 pickers. In v1 these stay intentionally
    /// Claude-first and static because the settings UI is built before any second
    /// provider contract is validated.
    var availableProviderIDs: [String] { ... }        // ["claude"] in v1 Phase 2
    func permissionModeOptions(for providerId: String) -> [String] { ... }
    func effortOptions(for providerId: String) -> [String] { ... }
    var themeOptions: [String] { ... }                // ["system", "light", "dark"]
    var availableSoundNames: [String] { ... }         // ["Glass", "Pop", "Tink", "Purr"]

    var defaultProvider: String { ... }
    var permissionMode: String { ... }
    var effort: String { ... }              // "low", "medium", "high", "max"
    var autoGenerateNames: Bool { ... }
    var autoTrustWorktrees: Bool { ... }
    var createWorktreeByDefault: Bool { ... }
    var theme: String { ... }  // "light", "dark", "system"
    var codeFontFamily: String { ... }
    var codeFontSize: Int { ... }
    var chatFontSize: Int { ... }
    var notificationsEnabled: Bool { ... }
    var osNotificationsEnabled: Bool { ... }
    var soundEnabled: Bool { ... }
    var soundName: String { ... }   // Always one of `availableSoundNames`; nil/unknown persisted values resolve to "Glass"
    var branchPrefix: String { ... }
    var pushOnCreate: Bool { ... }
    func providerConfig(for providerId: String) -> ProviderCustomConfig { ... }
    func updateProviderConfig(for providerId: String, _ transform: (inout ProviderCustomConfig) -> Void) { ... }

    // Each property setter writes to SettingsService and triggers observation
}
```

**Used by**: `SettingsScreen` in Phase 6 (middle pane when settings gear is clicked). Also read by other view models indirectly through `SettingsService`.

Minimal screen signature:

```swift
struct SettingsScreen: View {  // Skep/Views/Settings/SettingsScreen.swift
    let viewModel: SettingsViewModel
    let onClose: (() -> Void)?
}
```

`SettingsViewModel` should expose picker-safe values for fixed-option controls. In practice that means `defaultProvider`, `permissionMode`, `effort`, `theme`, and `soundName` already reflect the normalized `SettingsService.current` snapshot rather than surfacing unchecked persisted strings to Phase 6 pickers.

**Unit tests for SettingsViewModel** (inject `InMemorySettingsService`): cover each property getter/setter pair (reads from and writes to `SettingsService`) plus provider-config read/write helpers. Non-obvious:
- `providerConfig(for:)` returns a default empty config when the provider has no stored overrides yet
- `updateProviderConfig(for:_:)` creates the dictionary entry on first write and preserves unrelated provider entries
- `soundName` getter resolves nil/legacy-invalid persisted values to `"Glass"` so the picker always has a valid selection

**Snapshot tests for SettingsScreen (Phase 6 UI step):**
- General settings tab (thread defaults + notifications)
- General settings tab with notifications disabled (subordinate rows disabled, values preserved)
- Agents tab (provider overrides)
- Repository settings tab
- Interface settings tab (theme, fonts)
