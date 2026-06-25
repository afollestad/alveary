import Foundation
import SwiftData
import SwiftUI

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
                let didChangePinnedOrder = threadID.flatMap { self.modelContext.resolveThread(id: $0)?.isPinned } ?? false
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
        return AgentThreadOrdering.sorted(threads)
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

    func setThreadPinned(_ thread: AgentThread, isPinned: Bool) throws {
        let dbThread = try requireThread(thread)
        guard dbThread.isPinned != isPinned else {
            return
        }

        dbThread.isPinned = isPinned
        try modelContext.save()
        withAnimation(.easeInOut(duration: 0.15)) {
            threadOrderVersion += 1
        }
    }
}
