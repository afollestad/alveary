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
            guard notification.userInfo?[ThreadActivityNotificationKey.didChangeOrder] as? Bool == true else {
                return
            }
            Task { @MainActor [weak self] in
                withAnimation(.easeInOut(duration: 0.15)) {
                    self?.threadOrderVersion += 1
                }
            }
        }
    }

    func activeThreads(for project: Project) -> [AgentThread] {
        let projectPath = project.path
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.project?.path == projectPath
            }
        )

        let threads = (try? modelContext.fetch(descriptor)) ?? []
        return AgentThreadOrdering.sorted(threads)
    }
}
