import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testDeleteLegacyProjectlessHistoryRemovesRecordsAndAttachments() async throws {
        for archived in [false, true] {
            let fixture = try SidebarTestFixture()
            let thread = try insertLegacyProjectlessHistory(in: fixture)
            thread.archivedAt = archived ? .now : nil
            try fixture.context.save()
            let threadID = thread.persistentModelID

            try await fixture.viewModel.deleteThread(thread)

            XCTAssertNil(fixture.context.resolveThread(id: threadID))
            XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Conversation>()), 0)
            let removedAttachments = await fixture.attachmentStore.removedConversationIDs
            XCTAssertEqual(removedAttachments.sorted(), ["main", "side"])
            let removedWorktrees = await fixture.worktreeManager.removeCalls()
            XCTAssertTrue(removedWorktrees.isEmpty)
        }
    }

    func testDeleteSourceLessThreadPreservesItsGrantedFolders() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try insertLegacyProjectlessHistory(in: fixture)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("keep.txt")
        try Data("Shared files".utf8).write(to: file)
        thread.workspaceSnapshot = WorkspaceSnapshot(primarySource: nil, grants: [SourceFolderSnapshot(path: root.path)])
        try fixture.context.save()

        try await fixture.viewModel.deleteThread(thread)

        XCTAssertEqual(try Data(contentsOf: file), Data("Shared files".utf8))
    }

    func testDeleteSourceLessThreadRejectsUnresolvedCleanupMetadataBeforeCommit() async throws {
        let mutations: [(String, (AgentThread) -> Void)] = [
            ("worktree", { $0.worktreePath = "/missing/worktree" }),
            ("branch", { $0.branch = "af/owned" }),
            ("worktree setup", { $0.useWorktree = true }),
            ("pending branch", { $0.pendingCleanupBranches = ["af/pending"] }),
            ("private root", { $0.taskPrimaryRoot = "/missing/private" }),
            ("ownership strategy", { $0.taskWorkspaceOwnershipStrategyRawValue = "privateOwned" }),
            ("ownership marker", { $0.taskWorkspaceMarkerID = UUID().uuidString }),
            ("source provenance", { $0.taskSourceProjectPath = "/missing/source" })
        ]
        for (name, mutate) in mutations {
            let fixture = try SidebarTestFixture()
            let thread = try insertLegacyProjectlessHistory(in: fixture)
            mutate(thread)
            try fixture.context.save()
            let threadID = thread.persistentModelID

            do {
                try await fixture.viewModel.deleteThread(thread)
                XCTFail("Expected unresolved \(name) to block deletion")
            } catch SidebarViewModelError.threadMissingDeletionMetadata { }

            XCTAssertNotNil(fixture.context.resolveThread(id: threadID), name)
            let removedAttachments = await fixture.attachmentStore.removedConversationIDs
            XCTAssertTrue(removedAttachments.isEmpty, name)
            let removedWorktrees = await fixture.worktreeManager.removeCalls()
            XCTAssertTrue(removedWorktrees.isEmpty, name)
        }
    }

    private func insertLegacyProjectlessHistory(in fixture: SidebarTestFixture) throws -> AgentThread {
        let thread = AgentThread(name: "Legacy task", hasCompletedInitialSetup: true, mode: .project)
        // Older standalone history predates owned Task workspaces; migration cannot invent a source folder.
        thread.workspaceSnapshot = WorkspaceSnapshot(primarySource: nil, rootsExplicitlyManaged: false)
        thread.conversations = ["main", "side"].enumerated().map { index, id in
            Conversation(id: id, title: id, provider: "codex", isMain: index == 0, displayOrder: index, thread: thread)
        }
        fixture.context.insert(thread)
        try fixture.context.save()
        return thread
    }
}
