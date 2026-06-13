import AppKit
import SwiftData
@preconcurrency import UserNotifications

enum NotificationUserInfoKey {
    static let conversationId = "conversationId"
}

@MainActor
final class DefaultNotificationManager: NotificationManager {
    static let notificationTitle = "Alveary"

    private let settingsService: any SettingsService
    private let modelContainer: ModelContainer
    private let systemNotificationCenter: NotificationCenter
    private var hasRequestedAuthorizationThisLaunch = false
    private var appVisibilityObservers: [NSObjectProtocol] = []
    private var pendingBadgeUpdate: Task<Void, Never>?

    var isAppInForeground: @MainActor () -> Bool = {
        NSApp.isActive && NSApp.occlusionState.contains(.visible)
    }
    var activeConversationId: @MainActor () -> String? = { nil }
    var playInAppSound: @MainActor (String) -> Void = { name in
        NSSound(named: NSSound.Name(name))?.play()
    }
    typealias PostNotificationHandler = @MainActor (
        _ context: ConversationNotificationContext,
        _ message: String,
        _ playSound: Bool
    ) -> Void
    var onPostNotification: PostNotificationHandler?
    var onDismissDelivered: (@MainActor (_ conversationId: String) -> Void)?
    var setBadgeCount: @MainActor (Int) async -> Void = { count in
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }

    init(
        settingsService: any SettingsService,
        modelContainer: ModelContainer,
        systemNotificationCenter: NotificationCenter = .default
    ) {
        self.settingsService = settingsService
        self.modelContainer = modelContainer
        self.systemNotificationCenter = systemNotificationCenter

        let visibilityHandler: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleAppVisibilityChanged()
            }
        }
        appVisibilityObservers = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didChangeOcclusionStateNotification
        ].map { name in
            systemNotificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main,
                using: visibilityHandler
            )
        }
    }

    deinit {
        MainActor.assumeIsolated {
            for observer in appVisibilityObservers {
                systemNotificationCenter.removeObserver(observer)
            }
        }
    }

    func handleEvent(_ event: ConversationEvent, conversationId: String) {
        let settings = settingsService.current
        guard settings.notifications.enabled,
              let baseMessage = notificationMessage(for: event) else {
            return
        }

        if isActivelyViewing(conversationId: conversationId) {
            playInAppSoundIfNeeded(settings: settings)
            return
        }

        markConversationUnread(conversationId: conversationId)
        refreshBadgeCount()

        guard settings.notifications.osNotifications else {
            playInAppSoundIfNeeded(settings: settings)
            return
        }

        let context = resolveContext(for: conversationId)
        let message = appendContextSuffix(to: baseMessage, context: context)

        dispatchOSNotification(
            context: context,
            message: message,
            playSound: settings.notifications.sound
        )
    }

    func markConversationRead(conversationId: String) {
        let didChangeUnreadState = setConversationUnread(conversationId: conversationId, isUnread: false)
        dismissDeliveredNotifications(conversationId: conversationId)
        if didChangeUnreadState {
            refreshBadgeCount()
        }
    }

    func handleAppVisibilityChanged() {
        if isAppInForeground(), let conversationId = activeConversationId() {
            markConversationRead(conversationId: conversationId)
        } else {
            refreshBadgeCount()
        }
    }

    func setActiveConversationProvider(_ provider: @escaping @MainActor () -> String?) {
        activeConversationId = provider
    }

    func refreshBadgeCount() {
        let count = unreadConversationCount()

        // Chain each badge update to the previous one so `setBadgeCount` calls apply in submission
        // order. Without this, multiple in-flight Tasks could complete in any order and leave the
        // dock icon showing a stale count (e.g. a rapid mark-unread + mark-read sequence could
        // land on the higher value).
        let previous = pendingBadgeUpdate
        let setBadge = setBadgeCount
        pendingBadgeUpdate = Task { @MainActor in
            _ = await previous?.value
            await setBadge(count)
        }
    }

    /// Await the tail of the chained badge-update task. Tests call this to ensure assertions run
    /// after the async `setBadgeCount` closure resolves.
    func awaitPendingBadgeUpdate() async {
        _ = await pendingBadgeUpdate?.value
    }

    private func isActivelyViewing(conversationId: String) -> Bool {
        isAppInForeground() && activeConversationId() == conversationId
    }

    private func notificationMessage(for event: ConversationEvent) -> String? {
        switch event {
        case .stop(let stopMessage):
            return stopMessage ?? "Your agent has finished working"
        case .notification(let type, let notificationText):
            return notificationMessage(for: type, text: notificationText)
        case .tokens(_, _, _, _, let isError, let stopReason, _, _, _, _, let permissionDenials, _):
            return tokenNotificationMessage(
                isError: isError,
                stopReason: stopReason,
                permissionDenials: permissionDenials
            )
        case .toolApprovalRequested(let request):
            return request.notificationMessage
        case .error(let errorMessage):
            return errorMessage.isEmpty ? "Your agent encountered an error" : errorMessage
        case .contextCompactionStarted, .contextCompactionCompleted, .contextCompactionFailed:
            return nil
        default:
            return nil
        }
    }

    private func notificationMessage(for type: String, text: String?) -> String? {
        switch type {
        case "idle_prompt":
            return text ?? "Your agent is waiting for input"
        case "permission_prompt":
            return text ?? "Your agent needs permission"
        default:
            return nil
        }
    }

    private func tokenNotificationMessage(
        isError: Bool,
        stopReason: String?,
        permissionDenials: [PermissionDenialSummary]
    ) -> String? {
        if !permissionDenials.isEmpty {
            return "Your agent needs permission"
        }

        if isError {
            return ConversationErrorDisplayPolicy.notificationErrorMessage(stopReason: stopReason)
        }

        guard stopReason != ConversationEvent.interimUsageStopReason,
              stopReason != "tool_deferred" else {
            return nil
        }

        return "Your agent has finished working"
    }

    private func playInAppSoundIfNeeded(settings: AppSettings) {
        guard settings.notifications.sound else {
            return
        }

        playInAppSound(settings.notifications.soundName ?? NotificationSettings.defaultSoundName)
    }

    private func markConversationUnread(conversationId: String) {
        _ = setConversationUnread(conversationId: conversationId, isUnread: true)
    }

    private func setConversationUnread(conversationId: String, isUnread: Bool) -> Bool {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { conversation in
            conversation.id == conversationId
        })

        guard let conversation = try? context.fetch(descriptor).first,
              conversation.isUnread != isUnread else {
            return false
        }

        conversation.isUnread = isUnread
        try? context.save()

        // `.agentStatusChanged` is a shared bus on `.default` — see the Notification.Name declaration.
        NotificationCenter.default.post(
            name: .agentStatusChanged,
            object: nil,
            userInfo: ["conversationId": conversationId]
        )
        return true
    }

    private func unreadConversationCount() -> Int {
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { conversation in
            conversation.isUnread == true && conversation.thread?.archivedAt == nil
        })
        return (try? modelContainer.mainContext.fetchCount(descriptor)) ?? 0
    }

    private func dismissDeliveredNotifications(conversationId: String) {
        if let onDismissDelivered {
            onDismissDelivered(conversationId)
            return
        }

        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [conversationId])
    }

    private func resolveContext(for conversationId: String) -> ConversationNotificationContext {
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { conversation in
            conversation.id == conversationId
        })

        guard let conversation = try? modelContainer.mainContext.fetch(descriptor).first else {
            return ConversationNotificationContext(
                conversationId: conversationId,
                threadId: nil,
                threadName: nil,
                conversationName: nil
            )
        }

        let thread = conversation.thread
        let siblingCount = thread.map { conversationCount(in: $0) } ?? 1
        let conversationName = siblingCount > 1 ? conversation.displayName() : nil

        return ConversationNotificationContext(
            conversationId: conversationId,
            threadId: thread?.persistentModelID,
            threadName: thread?.displayName(),
            conversationName: conversationName
        )
    }

    private func conversationCount(in thread: AgentThread) -> Int {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { conversation in
            conversation.thread?.persistentModelID == threadID
        })
        return (try? modelContainer.mainContext.fetchCount(descriptor)) ?? 1
    }

    private func appendContextSuffix(to baseMessage: String, context: ConversationNotificationContext) -> String {
        guard let suffix = context.inPhrase() else {
            return baseMessage
        }

        return "\(baseMessage) \(suffix)"
    }

    private func dispatchOSNotification(
        context: ConversationNotificationContext,
        message: String,
        playSound: Bool
    ) {
        if let onPostNotification {
            onPostNotification(context, message, playSound)
            return
        }

        let center = UNUserNotificationCenter.current()
        let request = makeNotificationRequest(
            context: context,
            message: message,
            playSound: playSound
        )

        Task { @MainActor in
            await postAgentNotification(request, with: center)
        }
    }

    func postAgentNotification(_ request: UNNotificationRequest, with center: UNUserNotificationCenter) async {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            try? await center.add(request)
        case .notDetermined:
            guard !hasRequestedAuthorizationThisLaunch else {
                return
            }
            hasRequestedAuthorizationThisLaunch = true
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else {
                return
            }
            try? await center.add(request)
        case .denied:
            return
        @unknown default:
            return
        }
    }

    func makeNotificationRequest(
        context: ConversationNotificationContext,
        message: String,
        playSound: Bool
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = Self.notificationTitle
        content.body = message
        content.userInfo = [NotificationUserInfoKey.conversationId: context.conversationId]
        if playSound {
            content.sound = .default
        }

        // Identifier intentionally equals the conversation id. A new event for the same
        // conversation *replaces* any pending banner (so stale "finished working" notifications
        // don't pile up once newer events arrive) and `removeDeliveredNotifications(withIdentifiers:)`
        // can target the conversation precisely on mark-read.
        return UNNotificationRequest(
            identifier: context.conversationId,
            content: content,
            trigger: nil
        )
    }
}

struct ConversationNotificationContext: Equatable, Sendable {
    let conversationId: String
    let threadId: PersistentIdentifier?
    let threadName: String?
    let conversationName: String?

    func inPhrase() -> String? {
        switch (threadName, conversationName) {
        case let (threadName?, conversationName?):
            return "in \"\(threadName)\" / \"\(conversationName)\""
        case let (threadName?, nil):
            return "in \"\(threadName)\""
        default:
            return nil
        }
    }
}
