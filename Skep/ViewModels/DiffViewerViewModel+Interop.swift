import Foundation

extension DiffViewerViewModel {
    nonisolated internal static func dispatchWatchEvent(changedPaths: Set<String>, owner: DiffViewerViewModel?) {
        guard let owner else {
            return
        }

        Task { @MainActor [weak owner] in
            owner?.handleFSEventsForTesting(changedPaths: changedPaths)
        }
    }
}

extension Notification.Name {
    static let appWillTerminate = Notification.Name("appWillTerminate")
}
