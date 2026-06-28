import Foundation
import SwiftData
import SwiftUI

struct SidebarPinnedItem: Identifiable {
    enum Kind {
        case project(Project)
        case thread(AgentThread)
    }

    let kind: Kind
    let activityDate: Date?

    init(project: Project, activityDate: Date?) {
        kind = .project(project)
        self.activityDate = activityDate
    }

    init(thread: AgentThread) {
        kind = .thread(thread)
        activityDate = thread.modifiedAt
    }

    var id: String {
        switch kind {
        case .project(let project):
            "project:\(project.path)"
        case .thread(let thread):
            "thread:\(String(describing: thread.persistentModelID))"
        }
    }

    var sidebarItem: SidebarItem {
        switch kind {
        case .project(let project):
            .project(project)
        case .thread(let thread):
            .thread(thread)
        }
    }

    var displayName: String {
        switch kind {
        case .project(let project):
            project.name
        case .thread(let thread):
            thread.displayName()
        }
    }

    var stableID: String {
        switch kind {
        case .project(let project):
            project.path
        case .thread(let thread):
            String(describing: thread.persistentModelID)
        }
    }
}

enum SidebarPinnedItemOrdering {
    @MainActor
    static func sorted(_ items: [SidebarPinnedItem]) -> [SidebarPinnedItem] {
        items.sorted(by: compare)
    }

    @MainActor
    static func compare(_ lhs: SidebarPinnedItem, _ rhs: SidebarPinnedItem) -> Bool {
        switch (lhs.activityDate, rhs.activityDate) {
        case (.some(let lhsActivity), .some(let rhsActivity)) where lhsActivity != rhsActivity:
            return lhsActivity > rhsActivity
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        let nameComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.stableID < rhs.stableID
    }
}

extension SidebarViewModel {
    func installThreadActivityObserver() {
        threadActivityObserver = NotificationCenter.default.addObserver(
            forName: .threadActivityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if notification.userInfo?[ThreadActivityNotificationKey.isBackfill] as? Bool == true {
                Task { @MainActor [weak self] in
                    self?.statusVersion += 1
                }
                return
            }
            let didChangeOrder = notification.userInfo?[ThreadActivityNotificationKey.didChangeOrder] as? Bool == true
            let threadID = notification.userInfo?[ThreadActivityNotificationKey.threadID] as? PersistentIdentifier
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let didChangePinnedOrder = threadID.flatMap { threadID -> Bool? in
                    guard let thread = self.modelContext.resolveThread(id: threadID) else {
                        return nil
                    }
                    return thread.isPinned || thread.project?.isPinned == true
                } ?? false
                guard didChangeOrder || didChangePinnedOrder else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.15)) {
                    self.threadOrderVersion += 1
                }
            }
        }
    }

    func pinnedThreads() -> [AgentThread] {
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isPinned == true
            }
        )

        let threads = (try? modelContext.fetch(descriptor)) ?? []
        return AgentThreadOrdering.sorted(threads.filter { $0.project?.isPinned != true })
    }

    func pinnedItems(projects: [Project]) -> [SidebarPinnedItem] {
        let projectItems = projects
            .filter(\.isPinned)
            .map { project in
                SidebarPinnedItem(
                    project: project,
                    activityDate: latestUnarchivedThreadModifiedAt(for: project)
                )
            }
        let threadItems = pinnedThreads().map(SidebarPinnedItem.init(thread:))
        return SidebarPinnedItemOrdering.sorted(projectItems + threadItems)
    }

    func activeThreads(for project: Project) -> [AgentThread] {
        let projectPath = project.path
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isPinned == false && thread.project?.path == projectPath
            }
        )

        let threads = (try? modelContext.fetch(descriptor)) ?? []
        return AgentThreadOrdering.sorted(threads)
    }

    func hasAnyActiveThreads(for project: Project) -> Bool {
        let projectPath = project.path
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.project?.path == projectPath
            }
        )

        return ((try? modelContext.fetch(descriptor)) ?? []).isEmpty == false
    }

    func setProjectPinned(_ project: Project, isPinned: Bool) throws {
        let dbProject = try requireProject(project)
        let projectPath = dbProject.path
        let childThreads = unarchivedThreads(projectPath: projectPath)
        var didChange = false

        if dbProject.isPinned != isPinned {
            dbProject.isPinned = isPinned
            didChange = true
        }

        for childThread in childThreads where childThread.isPinned {
            childThread.isPinned = false
            didChange = true
        }

        guard didChange else {
            return
        }

        try modelContext.save()
        withAnimation(.easeInOut(duration: 0.15)) {
            threadOrderVersion += 1
        }
    }

    func setThreadPinned(_ thread: AgentThread, isPinned: Bool) throws {
        let dbThread = try requireThread(thread)
        if isPinned, dbThread.project?.isPinned == true {
            return
        }
        guard dbThread.isPinned != isPinned else {
            return
        }

        dbThread.isPinned = isPinned
        try modelContext.save()
        withAnimation(.easeInOut(duration: 0.15)) {
            threadOrderVersion += 1
        }
    }

    private func latestUnarchivedThreadModifiedAt(for project: Project) -> Date? {
        unarchivedThreads(projectPath: project.path).compactMap(\.modifiedAt).max()
    }

    private func unarchivedThreads(projectPath: String) -> [AgentThread] {
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.project?.path == projectPath
            }
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
