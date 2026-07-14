import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppState {
    private static let maxUnexpectedErrorToasts = 3

    var selectedSidebarItem: SidebarItem?
    private(set) var isRightPaneVisible = false
    private(set) var isLeftPaneVisible = true
    private(set) var isTerminalPaneVisible = false
    private(set) var unexpectedErrorToasts: [UnexpectedErrorToast] = []
    var pendingCommand: CommandRequest?
    var pendingCommitMessageGenerationRequest: CommitMessageGenerationRequest?
    private(set) var pendingSettingsTargetPage: AppSettings.SettingsPage?
    var imagePreviewRequest: AppImagePreviewRequest?
    var selectedConversationIDs: [PersistentIdentifier: PersistentIdentifier] = [:]
    var previousSelection: SidebarBookmark?
    // Set by commands that want the BlockInput composer to grab focus once a
    // thread view mounts (e.g. ⌘N). The sidebar's `selectedSidebarItem`
    // `.onChange` hook skips its usual focus claim while this is non-nil.
    var pendingComposerFocusToken: UUID?

    func openSettings(targetPage: AppSettings.SettingsPage? = nil) {
        if selectedSidebarItem != .settings {
            previousSelection = selectedSidebarItem.flatMap(SidebarBookmark.init)
        }
        pendingSettingsTargetPage = targetPage
        selectedSidebarItem = .settings
    }

    func clearPendingSettingsTargetPage(_ page: AppSettings.SettingsPage) {
        guard pendingSettingsTargetPage == page else {
            return
        }
        pendingSettingsTargetPage = nil
    }

    func startNewThreadFlow(mode: AgentThreadMode = .project) {
        pendingCommand = .newThread(UUID(), mode: mode)
    }

    func requestComposerFocus() {
        pendingComposerFocusToken = UUID()
    }

    func presentUnexpectedError(message: String, id: UUID = UUID()) {
        let toast = UnexpectedErrorToast(id: id, message: message)
        unexpectedErrorToasts = Array((unexpectedErrorToasts + [toast]).suffix(Self.maxUnexpectedErrorToasts))
    }

    func presentSuccessFeedback(message: String, id: UUID = UUID()) {
        let toast = UnexpectedErrorToast(id: id, message: message, kind: .success)
        unexpectedErrorToasts = Array((unexpectedErrorToasts + [toast]).suffix(Self.maxUnexpectedErrorToasts))
    }

    func dismissUnexpectedErrorToast(id: UnexpectedErrorToast.ID) {
        unexpectedErrorToasts.removeAll { $0.id == id }
    }

    func presentImagePreview(_ request: AppImagePreviewRequest) {
        imagePreviewRequest = request
    }

    func dismissImagePreview() {
        imagePreviewRequest = nil
    }

    func openNewProjectFlow() {
        pendingCommand = .newProject(UUID())
    }

    func showTerminalPane() {
        isTerminalPaneVisible = true
    }

    func hideTerminalPane() {
        isTerminalPaneVisible = false
    }

    func toggleRightPane() {
        isRightPaneVisible.toggle()
    }

    func showRightPane() {
        isRightPaneVisible = true
    }

    func hideRightPane() {
        isRightPaneVisible = false
    }

    func setLeftPaneVisible(_ isVisible: Bool) {
        isLeftPaneVisible = isVisible
    }

    func requestCommitMessageGeneration(
        prompt: String,
        conversationID: PersistentIdentifier,
        completion: @escaping @MainActor (Result<String, Error>) -> Void
    ) {
        pendingCommitMessageGenerationRequest = CommitMessageGenerationRequest(
            id: UUID(),
            conversationID: conversationID,
            prompt: prompt,
            completion: completion
        )
    }

    func clearCommitMessageGenerationRequest(id: UUID) {
        if pendingCommitMessageGenerationRequest?.id == id {
            pendingCommitMessageGenerationRequest = nil
        }
    }

    func cancelPendingCommitMessageGenerationRequest(
        error: CommitMessageGenerationError = .activeConversationChanged
    ) {
        guard let request = pendingCommitMessageGenerationRequest else {
            return
        }

        pendingCommitMessageGenerationRequest = nil
        request.completion(.failure(error))
    }

    func selectedConversation(in thread: AgentThread, conversations: [Conversation]) -> Conversation? {
        let sortedConversations = sortedConversationList(conversations)

        if let selectedID = selectedConversationIDs[thread.persistentModelID],
           let selectedConversation = sortedConversations.first(where: { $0.persistentModelID == selectedID }) {
            return selectedConversation
        }

        return sortedConversations.first(where: { $0.isMain }) ?? sortedConversations.first
    }

    func repairSelectedConversationIfNeeded(for thread: AgentThread, conversations: [Conversation]) {
        let threadID = thread.persistentModelID
        let resolvedConversationID = selectedConversation(in: thread, conversations: conversations)?.persistentModelID

        repairSelectedConversation(threadID: threadID, resolvedConversationID: resolvedConversationID)
    }

    private func repairSelectedConversation(threadID: PersistentIdentifier, resolvedConversationID: PersistentIdentifier?) {
        if let resolvedConversationID {
            if selectedConversationIDs[threadID] != resolvedConversationID {
                selectedConversationIDs[threadID] = resolvedConversationID
            }
        } else {
            selectedConversationIDs.removeValue(forKey: threadID)
        }
    }

    func selectConversation(_ conversation: Conversation, in thread: AgentThread) {
        if pendingCommitMessageGenerationRequest?.conversationID != conversation.persistentModelID {
            cancelPendingCommitMessageGenerationRequest()
        }
        selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
    }

    private func sortedConversationList(_ conversations: [Conversation]) -> [Conversation] {
        conversations.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            if $0.isMain != $1.isMain {
                return $0.isMain && !$1.isMain
            }
            return $0.id < $1.id
        }
    }

    enum SidebarBookmark: Hashable {
        case skills
        case mcp
        case scheduled
        case projectPath(String)
        case threadId(PersistentIdentifier)

        init?(_ item: SidebarItem) {
            switch item {
            case .skills:
                self = .skills
            case .mcp:
                self = .mcp
            case .scheduled:
                self = .scheduled
            case .project(let project):
                self = .projectPath(project.path)
            case .thread(let thread):
                self = .threadId(thread.persistentModelID)
            case .settings:
                return nil
            }
        }
    }

    enum CommandRequest: Equatable {
        case newThread(UUID, mode: AgentThreadMode)
        case newProject(UUID)

        var id: UUID {
            switch self {
            case .newThread(let id, _), .newProject(let id):
                return id
            }
        }
    }

    enum AppToastKind: Equatable, Sendable {
        case error
        case success
    }

    struct CommitMessageGenerationRequest {
        let id: UUID
        let conversationID: PersistentIdentifier
        let prompt: String
        let completion: @MainActor (Result<String, Error>) -> Void
    }

    struct UnexpectedErrorToast: Identifiable, Equatable, Sendable {
        let id: UUID
        let message: String
        let kind: AppToastKind

        init(id: UUID, message: String, kind: AppToastKind = .error) {
            self.id = id
            self.message = message
            self.kind = kind
        }
    }
}

enum CommitMessageGenerationError: LocalizedError, Sendable, Equatable {
    case activeConversationChanged
    case busy
    case emptyResponse
    case approvalRequested
    case interrupted
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .activeConversationChanged:
            return "Active conversation changed while generating the commit message."
        case .busy:
            return "Wait for the current conversation action to finish before generating a commit message."
        case .emptyResponse:
            return "Commit message generation returned no message."
        case .approvalRequested:
            return "Commit message generation paused because the hidden prompt requested approval."
        case .interrupted:
            return "Commit message generation was interrupted."
        case .failed(let message):
            return message
        }
    }
}

enum SidebarItem: Hashable {
    case skills
    case mcp
    case scheduled
    case project(Project)
    case thread(AgentThread)
    case settings

    var canCommitDiffChanges: Bool {
        switch self {
        case .project:
            return true
        case .thread(let thread):
            return thread.effectiveMode == .project
        case .skills, .mcp, .scheduled, .settings:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .skills:
            hasher.combine("skills")
        case .mcp:
            hasher.combine("mcp")
        case .scheduled:
            hasher.combine("scheduled")
        case .settings:
            hasher.combine("settings")
        case .project(let project):
            hasher.combine(project.path)
        case .thread(let thread):
            hasher.combine(thread.persistentModelID)
        }
    }

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        switch (lhs, rhs) {
        case (.skills, .skills), (.mcp, .mcp), (.scheduled, .scheduled), (.settings, .settings):
            return true
        case (.project(let left), .project(let right)):
            return left.path == right.path
        case (.thread(let left), .thread(let right)):
            return left.persistentModelID == right.persistentModelID
        default:
            return false
        }
    }
}
