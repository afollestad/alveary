import Foundation
import SwiftData

@testable import Alveary

@MainActor
extension SidebarTestFixture {
    /// A real, non-draft Task with an owned private workspace on disk — the shape a user has after
    /// starting a Task from the sidebar.
    func materializedTask(named name: String) async throws -> AgentThread {
        let draft = try await viewModel.openTaskDraft()
        let task = try requireThread(draft.persistentModelID)
        task.name = name
        task.hasCustomName = true
        task.isDraft = false
        task.hasCompletedInitialSetup = true
        try context.save()
        viewModel.noteDraftMaterialized(mode: .task)
        return task
    }

    func requireThread(_ id: PersistentIdentifier) throws -> AgentThread {
        guard let thread = context.resolveThread(id: id) else {
            throw SidebarFixtureError.threadMissing
        }
        return thread
    }

    /// A real directory on disk, since grant canonicalization rejects paths that do not exist.
    func makeTemporaryDirectory(named name: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath().path
    }
}
