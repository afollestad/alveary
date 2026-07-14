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
}
