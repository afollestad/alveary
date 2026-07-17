import SwiftData

extension ContentView {
    func canViewThread(_ id: PersistentIdentifier) -> Bool {
        guard currentVisibleThreadID != id,
              let thread = uiModelContext.resolveThread(id: id),
              !thread.isDraft else {
            return false
        }

        return thread.archivedAt == nil
    }

    func viewThread(_ id: PersistentIdentifier) {
        guard let thread = uiModelContext.resolveThread(id: id),
              thread.archivedAt == nil,
              !thread.isDraft else {
            return
        }

        appState.selectedSidebarItem = .thread(thread)
    }

    private var currentVisibleThreadID: PersistentIdentifier? {
        guard case .thread(let thread) = appState.selectedSidebarItem,
              !thread.isDraft else {
            return nil
        }

        return thread.persistentModelID
    }
}
