import Foundation
import Observation
import SwiftData

struct ArchivedThreadItem: Identifiable, Equatable {
    let id: PersistentIdentifier
    let title: String
    let archivedAt: Date
    let projectPath: String?
    let projectName: String?
    /// Drives the delete confirmation copy, which differs for Task workspaces.
    let isTask: Bool
}

/// Groups archived threads by their `project` relationship. Threads with no project
/// share the leading unnamed section; every other project gets its own titled section.
struct ArchivedThreadSection: Identifiable, Equatable {
    let id: String
    let title: String?
    let items: [ArchivedThreadItem]
}

enum ArchivedProjectFilter: Hashable {
    case all
    case noProject
    case project(path: String)
}

@MainActor
@Observable
final class ArchivedThreadsViewModel {
    typealias FetchArchivedThreads = @MainActor () throws -> [AgentThread]

    private let modelContext: ModelContext
    private let sidebarViewModel: SidebarViewModel
    private let appState: AppState
    private let settingsService: any SettingsService
    private let fetchArchivedThreads: FetchArchivedThreads
    private var loadErrorMessage: String?
    private var operationErrorMessage: String?

    private(set) var items: [ArchivedThreadItem] = []
    private(set) var busyThreadIDs: Set<ArchivedThreadItem.ID> = []
    private(set) var pendingPermanentDeletion: ArchivedThreadItem?
    private(set) var pendingRestore: ArchivedThreadItem?

    var searchQuery: String = ""
    var projectFilter: ArchivedProjectFilter = .all

    var errorMessage: String? {
        operationErrorMessage ?? loadErrorMessage
    }

    init(
        modelContext: ModelContext,
        sidebarViewModel: SidebarViewModel,
        appState: AppState,
        settingsService: any SettingsService,
        fetchArchivedThreads: FetchArchivedThreads? = nil
    ) {
        self.modelContext = modelContext
        self.sidebarViewModel = sidebarViewModel
        self.appState = appState
        self.settingsService = settingsService
        self.fetchArchivedThreads = fetchArchivedThreads ?? {
            let descriptor = FetchDescriptor<AgentThread>(
                predicate: #Predicate { thread in
                    thread.archivedAt != nil && thread.isDraft == false
                }
            )
            return try modelContext.fetch(descriptor)
        }
    }

    /// Sections for the current search query and project filter, project-less first.
    var sections: [ArchivedThreadSection] {
        Self.makeSections(from: visibleItems)
    }

    /// `.all` plus only those buckets that actually hold archived threads.
    var projectFilterOptions: [ArchivedProjectFilter] {
        var options: [ArchivedProjectFilter] = [.all]
        if items.contains(where: { $0.projectPath == nil }) {
            options.append(.noProject)
        }
        options.append(contentsOf: Self.orderedProjectBuckets(from: items).map { .project(path: $0.path) })
        return options
    }

    func projectFilterLabel(_ filter: ArchivedProjectFilter) -> String {
        switch filter {
        case .all:
            return "All Projects"
        case .noProject:
            return "No Project"
        case .project(let path):
            return items.first { $0.projectPath == path }?.projectName ?? path
        }
    }

    func refresh() {
        do {
            items = try fetchArchivedThreads()
                .sorted(by: Self.isOrderedBefore)
                .compactMap(Self.makeItem)
            normalizeProjectFilter()
            loadErrorMessage = nil
        } catch {
            items = []
            normalizeProjectFilter()
            loadErrorMessage = "Archived threads could not be loaded: \(error.localizedDescription)"
        }
    }

    /// Every archive, restore, and delete lands here; the list spans all thread modes,
    /// so there is no mode gate to check before refreshing.
    func handleThreadLifecycleChanged(_: Notification) {
        refresh()
    }

    func requestRestore(_ item: ArchivedThreadItem) {
        guard !busyThreadIDs.contains(item.id),
              items.contains(where: { $0.id == item.id }) else {
            return
        }
        pendingRestore = item
    }

    func cancelRestore() {
        pendingRestore = nil
    }

    func confirmRestore(_ item: ArchivedThreadItem) async {
        pendingRestore = nil
        await restore(item)
    }

    func restore(_ item: ArchivedThreadItem) async {
        guard beginOperation(for: item.id) else {
            return
        }
        defer { finishOperation(for: item.id) }

        guard let thread = archivedThread(id: item.id) else {
            refresh()
            return
        }

        do {
            try await sidebarViewModel.restoreThread(thread)
            refresh()
        } catch {
            operationErrorMessage = "The thread could not be restored: \(error.localizedDescription)"
            refresh()
        }
    }

    func requestPermanentDeletion(_ item: ArchivedThreadItem) {
        guard !busyThreadIDs.contains(item.id),
              items.contains(where: { $0.id == item.id }) else {
            return
        }
        pendingPermanentDeletion = item
    }

    func cancelPermanentDeletion() {
        pendingPermanentDeletion = nil
    }

    func confirmPermanentDeletion(_ item: ArchivedThreadItem) async {
        pendingPermanentDeletion = nil
        await permanentlyDelete(item)
    }

    func dismissError() {
        loadErrorMessage = nil
        operationErrorMessage = nil
    }
}

private extension ArchivedThreadsViewModel {
    var visibleItems: [ArchivedThreadItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard matchesProjectFilter(item) else {
                return false
            }
            return query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
        }
    }

    func matchesProjectFilter(_ item: ArchivedThreadItem) -> Bool {
        switch projectFilter {
        case .all:
            return true
        case .noProject:
            return item.projectPath == nil
        case .project(let path):
            return item.projectPath == path
        }
    }

    /// Keeps the picker honest when the last thread in the selected bucket leaves.
    func normalizeProjectFilter() {
        guard !projectFilterOptions.contains(projectFilter) else {
            return
        }
        projectFilter = .all
    }

    /// One grouping pass, because `sections` is recomputed on every `body` evaluation —
    /// including each keystroke in the search field. Bucketing per project and then
    /// re-filtering `items` for each bucket would make this O(projects × threads).
    static func makeSections(from items: [ArchivedThreadItem]) -> [ArchivedThreadSection] {
        var projectlessItems: [ArchivedThreadItem] = []
        var itemsByProjectPath: [String: [ArchivedThreadItem]] = [:]
        for item in items {
            guard let projectPath = item.projectPath else {
                projectlessItems.append(item)
                continue
            }
            itemsByProjectPath[projectPath, default: []].append(item)
        }

        var sections: [ArchivedThreadSection] = []
        if !projectlessItems.isEmpty {
            sections.append(ArchivedThreadSection(id: "no-project", title: nil, items: projectlessItems))
        }
        for bucket in orderedProjectBuckets(from: items) {
            guard let projectItems = itemsByProjectPath[bucket.path] else {
                continue
            }
            sections.append(
                ArchivedThreadSection(id: "project:\(bucket.path)", title: bucket.name, items: projectItems)
            )
        }
        return sections
    }

    /// Distinct project buckets ordered the way sidebar project rows are: name, then path.
    static func orderedProjectBuckets(from items: [ArchivedThreadItem]) -> [(path: String, name: String)] {
        var buckets: [String: String] = [:]
        for item in items {
            guard let path = item.projectPath else {
                continue
            }
            buckets[path] = item.projectName ?? path
        }
        return buckets
            .map { (path: $0.key, name: $0.value) }
            .sorted { left, right in
                let comparison = left.name.localizedCaseInsensitiveCompare(right.name)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return left.path < right.path
            }
    }

    static func makeItem(_ thread: AgentThread) -> ArchivedThreadItem? {
        guard let archivedAt = thread.archivedAt else {
            return nil
        }
        return ArchivedThreadItem(
            id: thread.persistentModelID,
            title: thread.displayName(),
            archivedAt: archivedAt,
            projectPath: thread.project?.path,
            projectName: thread.project?.name,
            isTask: thread.effectiveMode == .task
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

    func archivedThread(id: PersistentIdentifier) -> AgentThread? {
        guard let thread = modelContext.resolveThread(id: id),
              thread.archivedAt != nil,
              !thread.isDraft else {
            return nil
        }
        return thread
    }

    func beginOperation(for id: PersistentIdentifier) -> Bool {
        guard busyThreadIDs.insert(id).inserted else {
            return false
        }
        operationErrorMessage = nil
        return true
    }

    func finishOperation(for id: PersistentIdentifier) {
        busyThreadIDs.remove(id)
    }

    func permanentlyDelete(_ item: ArchivedThreadItem) async {
        guard beginOperation(for: item.id) else {
            return
        }
        defer { finishOperation(for: item.id) }

        guard let thread = archivedThread(id: item.id) else {
            refresh()
            return
        }
        let conversationIDs = Set(thread.conversations.map(\.persistentModelID))

        do {
            try await sidebarViewModel.deleteThread(thread) { [self] in
                self.sanitizeDeletedThreadState(
                    threadID: item.id,
                    conversationIDs: conversationIDs
                )
            }
            sanitizeDeletedThreadState(threadID: item.id, conversationIDs: conversationIDs)
            refresh()
        } catch {
            if modelContext.resolveThread(id: item.id) == nil {
                sanitizeDeletedThreadState(threadID: item.id, conversationIDs: conversationIDs)
                operationErrorMessage = "The thread was deleted, but cleanup did not finish: \(error.localizedDescription)"
            } else {
                operationErrorMessage = "The thread could not be deleted: \(error.localizedDescription)"
            }
            refresh()
        }
    }

    func sanitizeDeletedThreadState(
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
