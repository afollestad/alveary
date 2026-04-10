# Part 1e: Events and Notifications

Universal event model, config types, error types, and notification manager. Continues from Part 1d.

## Implementation Status

- [x] Universal event model and supporting config/error types
- [x] Notification manager protocol and default implementation

## Universal Event Model

Each provider emits different JSON, but adapters normalize into a universal event type. Defined here because `NotificationManager` and other foundational services depend on it.

```swift
struct ToolResultMetadata: Sendable {  // Skep/Services/Agent/ConversationEvent.swift
    let stderr: String?
    let interrupted: Bool
    let isImage: Bool
    let noOutputExpected: Bool
}

struct PermissionDenialSummary: Sendable {  // Skep/Services/Agent/ConversationEvent.swift
    let toolName: String
    let toolUseId: String?
}

enum ConversationEvent: Sendable {  // Skep/Services/Agent/ConversationEvent.swift
    case sessionInit(sessionId: String?)
    case message(role: String, content: String, parentToolUseId: String?)
    case messageChunk(text: String, parentToolUseId: String?)  // Partial text from stream_event (not persisted)
    case toolCall(id: String, name: String, input: String, parentToolUseId: String?, callerAgent: String?)
    case toolResult(id: String, output: String, isError: Bool, parentToolUseId: String?, metadata: ToolResultMetadata?)
    case thinking(content: String, parentToolUseId: String?)
    case tokens(input: Int, output: Int, cacheRead: Int, isError: Bool, stopReason: String?, durationMs: Int, costUsd: Double, permissionDenials: [PermissionDenialSummary])
    case subAgentStarted(toolUseId: String, description: String, taskType: String?)       // system/task_started
    case subAgentProgress(toolUseId: String, description: String?, lastToolName: String?, toolUses: Int, totalTokens: Int, durationMs: Int)  // system/task_progress
    case subAgentCompleted(toolUseId: String, status: String, toolUses: Int, totalTokens: Int, durationMs: Int)        // system/task_notification
    case notification(type: String, message: String?)    // Reserved for future providers; persisted + handled if emitted
    case stop(message: String?)                          // Reserved for future providers; persisted + handled if emitted
    case error(message: String)

    /// Convert to a SwiftData record for persistence.
    /// @MainActor because it accesses SwiftData `@Model` objects (`Conversation`,
    /// `ConversationEventRecord`) which are main-actor-isolated. All callers
    /// (`ConversationViewModel.handleEvent()`) are already `@MainActor`.
    @MainActor
    func toRecord(conversation: Conversation) -> ConversationEventRecord? {
        let record: ConversationEventRecord
        switch self {
        case .message(let role, let content, let parentToolUseId):
            record = ConversationEventRecord(type: "message", role: role, content: content)
            record.parentToolUseId = parentToolUseId
        case .toolCall(let id, let name, let input, let parentToolUseId, let callerAgent):
            record = ConversationEventRecord(type: "tool_call", toolId: id, toolName: name, toolInput: input)
            record.parentToolUseId = parentToolUseId
            record.callerAgent = callerAgent
        case .toolResult(let id, let output, let isError, let parentToolUseId, let metadata):
            record = ConversationEventRecord(
                type: "tool_result",
                toolId: id,
                toolOutput: output,
                toolOutputStderr: metadata?.stderr,
                toolOutputInterrupted: metadata?.interrupted ?? false,
                toolOutputIsImage: metadata?.isImage ?? false,
                toolOutputNoOutputExpected: metadata?.noOutputExpected ?? false,
                isError: isError
            )
            record.parentToolUseId = parentToolUseId
        case .thinking(let content, let parentToolUseId):
            record = ConversationEventRecord(type: "thinking", content: content)
            record.parentToolUseId = parentToolUseId
        case .tokens(let input, let output, let cacheRead, let isError, let stopReason, let durationMs, let costUsd, _):
            record = ConversationEventRecord(type: "tokens", isError: isError, tokenInput: input, tokenOutput: output, tokenCacheRead: cacheRead)
            record.stopReason = stopReason
            record.durationMs = durationMs
            record.costUsd = costUsd
        case .notification(let type, let message):
            record = ConversationEventRecord(type: "notification", content: message ?? "", notificationType: type)
        case .stop(let message):
            record = ConversationEventRecord(type: "stop", content: message ?? "")
        case .sessionInit(let sessionId):
            record = ConversationEventRecord(type: "session_init", content: sessionId ?? "")
        case .error(let message):
            record = ConversationEventRecord(type: "error", content: message)
        case .messageChunk:
            return nil
        case .subAgentStarted, .subAgentProgress, .subAgentCompleted:
            return nil
        }
        record.conversation = conversation
        record.conversationId = conversation.id
        return record
    }
}
```

`toRecord(conversation:)` is intentionally nil-returning for stream-only control events. Persisted history stays opt-in rather than crash-on-misuse, so a later call site that forgets to filter `.messageChunk` or sub-agent control events degrades into a skipped write instead of a trap.

`sessionInit` intentionally carries only the resumable session ID in the universal v1 event model. Richer provider-specific `system/init` metadata (for example slash commands or tool catalogs) stays adapter-owned until a later feature explicitly promotes it into shared types.

Notification invariant: adapters and higher layers should treat `.tokens`, `.stop`, `.notification`, and `.error` as terminal attention signals, but only one user-visible notification path should fire per completed turn. `DefaultNotificationManager` therefore reacts to the first terminal event it receives for that turn and ignores non-terminal chatter.

### Config Types

```swift
/// Per-adapter config passed to AgentAdapter methods (CLI flags, session ID, etc.)
struct AgentConfig: Sendable {  // Skep/Services/Agent/AgentConfig.swift
    let providerId: String
    let sessionId: String
    let workingDirectory: String
    let permissionMode: String?     // e.g. "bypassPermissions", "plan", "default"
    let model: String?              // e.g. "opus", "sonnet", or full model ID
    let effort: String?             // e.g. "low", "medium", "high", "max"
    let initialPrompt: String?      // First message to send
}

/// High-level spawn request from the UI layer, resolved into AgentConfig by AgentsManager
struct AgentSpawnConfig: Sendable {  // Skep/Services/Agent/AgentConfig.swift
    let providerId: String
    let workingDirectory: String
    let permissionMode: String?
    let model: String?              // e.g. "opus", "sonnet"
    let effort: String?             // e.g. "low", "medium", "high", "max"
    let initialPrompt: String?
}
```

### Error Types

```swift
enum AgentError: Error, Sendable {  // Skep/Services/Agent/AgentError.swift
    case cliNotInstalled(String)     // Provider ID
    case spawnFailed(String)         // Underlying error message
    case stdinClosed                 // Process stdin was unexpectedly closed
}
```

### Swift Example: Posting OS Notifications

```swift
import UserNotifications

@MainActor
protocol NotificationManager {  // Skep/Services/Notification/NotificationManager.swift
    func handleEvent(_ event: ConversationEvent, providerName: String, threadName: String?)
}

/// @MainActor because `NSApp.isActive` and `NSSound` must be accessed on the main thread.
/// The AgentsManager stream reader calls this via `await`, which hops to the main actor.
@MainActor
/// Note on testability: keep the system side effects behind simple per-instance
/// test hooks instead of adding container-wide wrapper services in v1. Tests can
/// replace the focus check, sound player, and notification poster with spies.
class DefaultNotificationManager: NotificationManager {  // Skep/Services/Notification/DefaultNotificationManager.swift
    private let settingsService: SettingsService
    private var hasRequestedAuthorizationThisLaunch = false
    /// Overridable for unit tests. Defaults to reading `NSApp.isActive`.
    /// Tests replace this closure with a fixed return value.
    var isFocused: @MainActor () -> Bool = { NSApp.isActive }
    /// Overridable for unit tests. Defaults to the real in-app sound path.
    var playInAppSound: @MainActor (String) -> Void = { name in
        NSSound(named: name)?.play()
    }
    /// Overridable for unit tests. When nil, the real OS-notification path is used.
    var onPostNotification: (@MainActor (_ providerName: String, _ threadName: String?, _ message: String, _ playSound: Bool) -> Void)?

    init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    func handleEvent(_ event: ConversationEvent, providerName: String, threadName: String?) {
        let settings = settingsService.current
        guard settings.notifications.enabled else { return }

        let message: String
        switch event {
        case .stop(let msg):
            message = msg ?? "Your agent has finished working"
        case .notification(let type, let msg):
            switch type {
            case "idle_prompt":
                message = msg ?? "Your agent is waiting for input"
            case "permission_prompt":
                message = msg ?? "Your agent needs permission"
            default:
                return
            }
        case .tokens(_, _, _, let isError, let stopReason, _, _, let permissionDenials):
            if !permissionDenials.isEmpty {
                message = "Your agent needs permission"
            } else if isError {
                let trimmedStopReason = stopReason?.trimmingCharacters(in: .whitespacesAndNewlines)
                message = (trimmedStopReason?.isEmpty == false) ? (trimmedStopReason ?? "") : "Your agent encountered an error"
            } else {
                message = "Your agent has finished working"
            }
        case .error(let errorMessage):
            message = errorMessage.isEmpty ? "Your agent encountered an error" : errorMessage
        default:
            return
        }

        let appFocused = isFocused()
        if appFocused {
            // In-app chime (no OS notification needed)
            if settings.notifications.sound {
                playInAppSound(settings.notifications.soundName ?? "Glass")
            }
        } else {
            guard settings.notifications.osNotifications else { return }
            if let onPostNotification {
                onPostNotification(providerName, threadName, message, settings.notifications.sound)
            } else {
                postAgentNotification(
                    providerName: providerName,
                    threadName: threadName,
                    message: message,
                    playSound: settings.notifications.sound
                )
            }
        }
    }

    private func postAgentNotification(
        providerName: String, threadName: String?,
        message: String, playSound: Bool
    ) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = threadName.map { "\(providerName) — \($0)" } ?? providerName
        content.body = message
        if playSound {
            // v1 uses the default notification sound. Custom per-user sound selection is
            // only applied to the in-app `NSSound` path because `UNNotificationSound`
            // can only reference bundled or app-container files.
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )
        let enqueueRequest = {
            center.add(request)
        }

        center.getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    enqueueRequest()
                case .notDetermined:
                    guard !self.hasRequestedAuthorizationThisLaunch else { return }
                    self.hasRequestedAuthorizationThisLaunch = true
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        guard granted else { return }
                        enqueueRequest()
                    }
                case .denied:
                    return
                @unknown default:
                    return
                }
            }
        }
    }
}
```

**Unit tests for NotificationManager** (inject `InMemorySettingsService`): test `handleEvent()` routing logic only — verify which events trigger sound vs. OS notification vs. nothing based on settings and focus state. Set `isFocused = { true/false }` and replace `playInAppSound` / `onPostNotification` with spies so the tests do not talk to `NSSound` or `UNUserNotificationCenter`. Non-obvious:
- Focus-based routing: focused → plays sound (no OS notification); unfocused → posts OS notification (no sound)
- `osNotifications` disabled + app unfocused → guard returns early, no sound AND no notification (not just "no OS notification")
- `.tokens(isError: false, permissionDenials: [])` routes as a completion notification
- `.tokens(isError: true, permissionDenials: [])` routes as an error notification, not a completion notification
- `.tokens(permissionDenials: [...])` routes as a permission-needed notification, not a completion notification
- Ignores non-notification events (`.message`, `.toolCall`, `.subAgentStarted`, etc.) — only `.stop`, `.tokens`, `.error`, and `.notification` trigger anything
