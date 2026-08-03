import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskProposalQueueTests {
    func testConfirmCreateRejectsChangedGrantAndKeepsProposalPending() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledTaskProposalGrant-\(UUID().uuidString)", isDirectory: true)
        let grant = root.appendingPathComponent("Grant", isDirectory: true)
        let replacement = root.appendingPathComponent("Replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: grant, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try ScheduledTaskProposalQueueFixture()
        let definitionDraft = fixture.makeDefinitionDraft(
            title: "Changed grant",
            grantedRoots: [grant.path]
        )
        let proposal = try fixture.insertProposal(
            id: "changed-grant",
            action: .create,
            definitionDraft: definitionDraft
        )
        let coordinator = fixture.makeCoordinator()
        let viewModel = fixture.makeScheduledTasksViewModel()
        let editorDraft = viewModel.makeProposalDraft(
            definitionDraft,
            definitionID: nil,
            expectedRevision: nil
        )
        try FileManager.default.removeItem(at: grant)
        try FileManager.default.createSymbolicLink(at: grant, withDestinationURL: replacement)

        XCTAssertFalse(
            coordinator.confirmEditorProposal(
                proposalID: proposal.id,
                draft: editorDraft,
                viewModel: viewModel
            )
        )

        XCTAssertEqual(coordinator.errorMessage, ScheduledTaskMutationError.workspaceRootsChanged.localizedDescription)
        XCTAssertEqual(coordinator.currentProposal?.id, proposal.id)
        XCTAssertNotNil(fixture.context.resolveScheduledTaskProposal(id: proposal.id))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ScheduledTask>()), 0)
    }

    /// A project-workspace proposal is confirmable only while its trusted Project relationship
    /// still names the same path its draft does. The host tool has to store the Project the draft
    /// names — including one an edit moved the task to — or this reads as a vanished Project.
    func testProjectProposalIsConfirmableOnlyWhileItsTrustedProjectMatchesTheDraft() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let project = Project(path: "/tmp/queue-project", name: "Queue Project")
        fixture.context.insert(project)
        try fixture.context.save()
        let definitionDraft = fixture.makeDefinitionDraft(
            title: "Runs in a project",
            grantedRoots: [],
            workspaceKind: .project,
            projectPath: project.path
        )

        let matched = try fixture.insertProposal(
            id: "matching-project",
            action: .create,
            definitionDraft: definitionDraft,
            project: project
        )
        let coordinator = fixture.makeCoordinator()
        XCTAssertNil(coordinator.presentation(forProposalID: matched.id)?.conflictMessage)

        // A proposal whose relationship points elsewhere is the "no longer available" case.
        fixture.context.delete(matched)
        try fixture.context.save()
        let mismatched = try fixture.insertProposal(
            id: "mismatched-project",
            action: .create,
            definitionDraft: definitionDraft,
            project: Project(path: "/tmp/queue-other-project", name: "Other")
        )
        coordinator.reload()

        XCTAssertNotNil(coordinator.presentation(forProposalID: mismatched.id)?.conflictMessage)
    }
}
