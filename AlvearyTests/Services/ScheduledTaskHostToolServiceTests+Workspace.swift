import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskHostToolServiceTests {
    func testCreateRejectsTaskGrantWhoseCanonicalTargetChanged() throws {
        let paths = try makeSymlinkGrantFixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: paths.workspace.path,
            grantedRoots: [paths.grant.path],
            ownershipStrategy: .privateOwned,
            ownershipMarkerID: "private-marker"
        )
        try replaceGrantWithSymlink(paths)
        let fixture = try ScheduledTaskHostToolFixture.task(descriptor: descriptor)

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: createArguments()
            )
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("changed"))
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    func testEditRejectsDefinitionGrantWhoseCanonicalTargetChanged() throws {
        let paths = try makeSymlinkGrantFixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fixture = try ScheduledTaskHostToolFixture.project()
        let target = fixture.insertDefinition(
            id: "definition-changed-grant",
            revision: 3,
            grantedRoots: [paths.grant.path]
        )
        try fixture.modelContext.save()
        try replaceGrantWithSymlink(paths)

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: [
                    "action": .string("edit"),
                    "task_id": .string(target.id),
                    "revision": .number(3),
                    "changes": .object(["title": .string("Only change the title")])
                ]
            )
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("changed"))
        XCTAssertEqual(target.grantedRoots, [paths.grant.path])
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    private func makeSymlinkGrantFixture() throws -> ScheduledTaskHostToolSymlinkGrantFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledTaskHostToolGrant-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("Workspace", isDirectory: true)
        let grant = root.appendingPathComponent("Grant", isDirectory: true)
        let replacement = root.appendingPathComponent("Replacement", isDirectory: true)
        for directory in [workspace, grant, replacement] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return ScheduledTaskHostToolSymlinkGrantFixture(
            root: root,
            workspace: workspace,
            grant: grant,
            replacement: replacement
        )
    }

    private func replaceGrantWithSymlink(_ paths: ScheduledTaskHostToolSymlinkGrantFixture) throws {
        try FileManager.default.removeItem(at: paths.grant)
        try FileManager.default.createSymbolicLink(at: paths.grant, withDestinationURL: paths.replacement)
    }
}

private struct ScheduledTaskHostToolSymlinkGrantFixture {
    let root: URL
    let workspace: URL
    let grant: URL
    let replacement: URL
}
