import SwiftData

extension SidebarViewModel {
    func persistDraftProjectMove() throws {
        try saveDraftProjectMove(modelContext)
    }

    func persistDeletionCommit() throws {
        try saveDeletionCommit(modelContext)
    }

    func persistThreadCreation() throws {
        try saveThreadCreation(modelContext)
    }

    func persistPendingSidebarChanges() throws {
        try savePendingSidebarChanges(modelContext)
    }

    func persistSidebarOrdering() throws {
        try saveSidebarOrdering(modelContext)
    }
}
