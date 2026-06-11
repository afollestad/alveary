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
    var pendingDiffAction: DiffActionRequest?
    var selectedConversationIDs: [PersistentIdentifier: PersistentIdentifier] = [:]
    var previousSelection: SidebarBookmark?
    // Set by commands that want the BlockInput composer to grab focus once a
    // thread view mounts (e.g. ⌘N). The sidebar's `selectedSidebarItem`
    // `.onChange` hook skips its usual focus claim while this is non-nil.
    var pendingComposerFocusToken: UUID?

    func openSettings() {
        if selectedSidebarItem != .settings {
            previousSelection = selectedSidebarItem.flatMap(SidebarBookmark.init)
        }
        selectedSidebarItem = .settings
    }

    func startNewThreadFlow() {
        pendingCommand = .newThread(UUID())
    }

    func requestComposerFocus() {
        pendingComposerFocusToken = UUID()
    }

    func presentUnexpectedError(message: String, id: UUID = UUID()) {
        let toast = UnexpectedErrorToast(id: id, message: message)
        unexpectedErrorToasts = Array((unexpectedErrorToasts + [toast]).suffix(Self.maxUnexpectedErrorToasts))
    }

    func dismissUnexpectedErrorToast(id: UnexpectedErrorToast.ID) {
        unexpectedErrorToasts.removeAll { $0.id == id }
    }

    func openNewProjectFlow() {
        pendingCommand = .newProject(UUID())
    }

    func toggleTerminalPane() {
        isTerminalPaneVisible.toggle()
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

    func requestDiffAction(message: String, conversationID: PersistentIdentifier) {
        pendingDiffAction = DiffActionRequest(
            id: UUID(),
            conversationID: conversationID,
            message: message
        )
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
        if pendingDiffAction?.conversationID != conversation.persistentModelID {
            pendingDiffAction = nil
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
        case projectPath(String)
        case threadId(PersistentIdentifier)

        init?(_ item: SidebarItem) {
            switch item {
            case .skills:
                self = .skills
            case .mcp:
                self = .mcp
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
        case newThread(UUID)
        case newProject(UUID)

        var id: UUID {
            switch self {
            case .newThread(let id), .newProject(let id):
                return id
            }
        }
    }

    struct DiffActionRequest: Equatable {
        let id: UUID
        let conversationID: PersistentIdentifier
        let message: String
    }

    struct UnexpectedErrorToast: Identifiable, Equatable, Sendable {
        let id: UUID
        let message: String
    }
}

enum SidebarItem: Hashable {
    case skills
    case mcp
    case project(Project)
    case thread(AgentThread)
    case settings

    var isThread: Bool {
        if case .thread = self {
            return true
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .skills:
            hasher.combine("skills")
        case .mcp:
            hasher.combine("mcp")
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
        case (.skills, .skills), (.mcp, .mcp), (.settings, .settings):
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
