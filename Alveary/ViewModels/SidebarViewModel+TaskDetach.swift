import Foundation
import SwiftData

extension SidebarViewModel {
    /// Pulls a project-nested Task back into `Tasks`. Placement is the only thing that changes:
    /// the Task keeps its workspace grants, so an agent mid-work does not lose folder access.
    func detachTaskFromProject(_ threadID: PersistentIdentifier) throws -> Bool {
        guard let thread = modelContext.resolveThread(id: threadID),
              thread.effectiveMode == .task,
              thread.project != nil,
              !thread.isDraft,
              thread.archivedAt == nil else {
            return false
        }
        if modelContext.hasChanges {
            try savePendingSidebarChanges(modelContext)
        }
        do {
            thread.project = nil
            _ = try normalizeSidebarOrderingForLifecycle()
            try savePendingSidebarChanges(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        refreshThreadOrder(animated: true)
        return true
    }
}
