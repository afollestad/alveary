import Foundation
import Observation
import SwiftData

struct ArchivedTaskSettingsItem: Identifiable, Equatable {
    let id: PersistentIdentifier
    let title: String
    let archivedAt: Date
}

@MainActor
@Observable
final class ArchivedTasksSettingsViewModel {
    typealias FetchArchivedTasks = @MainActor () throws -> [AgentThread]

    private let modelContext: ModelContext
    private let sidebarViewModel: SidebarViewModel
    private let appState: AppState
    private let settingsService: any SettingsService
    private let fetchArchivedTasks: FetchArchivedTasks
    private var loadErrorMessage: String?
    private var operationErrorMessage: String?

    private(set) var items: [ArchivedTaskSettingsItem] = []
    private(set) var busyTaskIDs: Set<PersistentIdentifier> = []
    private(set) var pendingPermanentDeletion: ArchivedTaskSettingsItem?

    var errorMessage: String? {
        operationErrorMessage ?? loadErrorMessage
    }

    init(
        modelContext: ModelContext,
        sidebarViewModel: SidebarViewModel,
        appState: AppState,
        settingsService: any SettingsService,
        fetchArchivedTasks: FetchArchivedTasks? = nil
    ) {
        self.modelContext = modelContext
        self.sidebarViewModel = sidebarViewModel
        self.appState = appState
        self.settingsService = settingsService
        self.fetchArchivedTasks = fetchArchivedTasks ?? {
            let taskMode = AgentThreadMode.task.rawValue
            let descriptor = FetchDescriptor<AgentThread>(
                predicate: #Predicate { thread in
                    thread.modeRawValue == taskMode && thread.archivedAt != nil && thread.isDraft == false
                }
            )
            return try modelContext.fetch(descriptor)
        }
    }

    func refresh() {
        do {
            items = try fetchArchivedTasks()
                .sorted(by: Self.isOrderedBefore)
                .compactMap(Self.makeItem)
            loadErrorMessage = nil
        } catch {
            items = []
            loadErrorMessage = "Archived tasks could not be loaded: \(error.localizedDescription)"
        }
    }

    func handleThreadLifecycleChanged(_ notification: Notification) {
        let mode = (notification.userInfo?[ThreadLifecycleNotificationKey.mode] as? String)
            .flatMap(AgentThreadMode.init(rawValue:))
        guard mode == .task else {
            return
        }
        refresh()
    }

    func restore(_ item: ArchivedTaskSettingsItem) async {
        guard beginOperation(for: item.id) else {
            return
        }
        defer { finishOperation(for: item.id) }

        guard let thread = archivedTask(id: item.id) else {
            refresh()
            return
        }

        do {
            try await sidebarViewModel.restoreThread(thread)
            refresh()
        } catch {
            operationErrorMessage = "The task could not be restored: \(error.localizedDescription)"
            refresh()
        }
    }

    func requestPermanentDeletion(_ item: ArchivedTaskSettingsItem) {
        guard !busyTaskIDs.contains(item.id),
              items.contains(where: { $0.id == item.id }) else {
            return
        }
        pendingPermanentDeletion = item
    }

    func cancelPermanentDeletion() {
        pendingPermanentDeletion = nil
    }

    func confirmPermanentDeletion(_ item: ArchivedTaskSettingsItem) async {
        pendingPermanentDeletion = nil
        await permanentlyDelete(item)
    }

    func dismissError() {
        loadErrorMessage = nil
        operationErrorMessage = nil
    }
}

private extension ArchivedTasksSettingsViewModel {
    static func makeItem(_ thread: AgentThread) -> ArchivedTaskSettingsItem? {
        guard let archivedAt = thread.archivedAt else {
            return nil
        }
        return ArchivedTaskSettingsItem(
            id: thread.persistentModelID,
            title: thread.displayName(),
            archivedAt: archivedAt
        )
    }

    static func isOrderedBefore(_ lhs: AgentThread, _ rhs: AgentThread) -> Bool {
        let leftArchiveDate = lhs.archivedAt ?? .distantPast
        let rightArchiveDate = rhs.archivedAt ?? .distantPast
        if leftArchiveDate != rightArchiveDate {
            return leftArchiveDate > rightArchiveDate
        }
        if lhs.modifiedAt != rhs.modifiedAt {
            return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
        }
        let nameComparison = lhs.displayName().localizedStandardCompare(rhs.displayName())
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return String(describing: lhs.persistentModelID) < String(describing: rhs.persistentModelID)
    }

    func archivedTask(id: PersistentIdentifier) -> AgentThread? {
        guard let thread = modelContext.resolveThread(id: id),
              thread.mode == .task,
              thread.archivedAt != nil,
              !thread.isDraft else {
            return nil
        }
        return thread
    }

    func beginOperation(for id: PersistentIdentifier) -> Bool {
        guard busyTaskIDs.insert(id).inserted else {
            return false
        }
        operationErrorMessage = nil
        return true
    }

    func finishOperation(for id: PersistentIdentifier) {
        busyTaskIDs.remove(id)
    }

    func permanentlyDelete(_ item: ArchivedTaskSettingsItem) async {
        guard beginOperation(for: item.id) else {
            return
        }
        defer { finishOperation(for: item.id) }

        guard let thread = archivedTask(id: item.id) else {
            refresh()
            return
        }
        let conversationIDs = Set(thread.conversations.map(\.persistentModelID))

        do {
            try await sidebarViewModel.deleteThread(thread)
            sanitizeDeletedTaskState(threadID: item.id, conversationIDs: conversationIDs)
            refresh()
        } catch {
            if modelContext.resolveThread(id: item.id) == nil {
                sanitizeDeletedTaskState(threadID: item.id, conversationIDs: conversationIDs)
                operationErrorMessage = "The task was deleted, but cleanup did not finish: \(error.localizedDescription)"
            } else {
                operationErrorMessage = "The task could not be deleted: \(error.localizedDescription)"
            }
            refresh()
        }
    }

    func sanitizeDeletedTaskState(
        threadID: PersistentIdentifier,
        conversationIDs: Set<PersistentIdentifier>
    ) {
        if case .thread(let selectedThread) = appState.selectedSidebarItem,
           selectedThread.persistentModelID == threadID {
            appState.selectedSidebarItem = nil
        }
        if case .threadId(let bookmarkedThreadID) = appState.previousSelection,
           bookmarkedThreadID == threadID {
            appState.previousSelection = nil
        }
        appState.selectedConversationIDs = appState.selectedConversationIDs.filter { candidateThreadID, conversationID in
            candidateThreadID != threadID && !conversationIDs.contains(conversationID)
        }

        if let request = appState.pendingCommitMessageGenerationRequest,
           conversationIDs.contains(request.conversationID) {
            appState.cancelPendingCommitMessageGenerationRequest()
        }

        let settings = settingsService.current
        if settings.lastOpenThreadID == threadID
            || settings.lastOpenConversationID.map(conversationIDs.contains) == true {
            settingsService.updateRestoreSelection(threadID: nil, conversationID: nil)
        }
    }
}
