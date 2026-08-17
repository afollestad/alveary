import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// Semantic rules for a requested destination or workspace: the thread has to be a real target,
/// the Project has to already be registered, and every grant must be an existing folder.
@MainActor
extension ScheduledTaskHostToolServiceTests {
    func testCreateIntoAnExistingThreadBindsTheTargetAndDisclosesThePin() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let target = try fixture.insertTargetThread(name: "Release chat", conversationID: "release-main")

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: createArguments().merging([
                    "destination": .string("existing_thread"),
                    "target_thread_id": .string("release-main")
                ]) { _, new in new }
            )
        )

        XCTAssertFalse(result.isError)
        let draft = try XCTUnwrap(try fixture.proposalDraft())
        XCTAssertEqual(draft.destination, .existingThread)
        XCTAssertEqual(draft.targetConversationID, "release-main")
        XCTAssertEqual(draft.workspaceKind, .privateWorkspace)
        XCTAssertNil(draft.projectPath)
        XCTAssertTrue(draft.grantedRoots.isEmpty)
        XCTAssertFalse(target.isPinned)
        // The pin is a real consequence of confirming, so the tool result says so up front.
        XCTAssertTrue(result.text.contains("Release chat"), result.text)
        XCTAssertTrue(result.text.contains("pinned when you confirm"), result.text)
    }

    func testCreateRejectsAnUnknownOrIneligibleTargetThread() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let archived = try fixture.insertTargetThread(name: "Archived", conversationID: "archived-main")
        archived.archivedAt = Date(timeIntervalSince1970: 10)
        try fixture.modelContext.save()

        let unknown = fixture.proposeExistingThread(targetThreadID: "no-such-thread")
        XCTAssertTrue(unknown.isError)
        XCTAssertTrue(unknown.text.contains("no longer exists"), unknown.text)

        let ineligible = fixture.proposeExistingThread(targetThreadID: "archived-main")
        XCTAssertTrue(ineligible.isError)
        XCTAssertTrue(ineligible.text.contains("cannot receive scheduled runs"), ineligible.text)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    func testCreateAcceptsARegisteredProjectWithAddedGrantsAndRefusesUnknownPaths() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        fixture.modelContext.insert(Project(path: "/tmp/other-project", name: "Other"))
        try fixture.modelContext.save()
        let grantDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledTaskHostToolProjectGrant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: grantDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: grantDir) }
        let grantPath = CanonicalPath.normalize(grantDir.path)

        // A Project selection may carry folder grants alongside it, like the editor pane.
        let accepted = fixture.proposeWorkspace([
            "kind": .string("project"),
            "project_path": .string("/tmp/other-project"),
            "granted_roots": .array([.string(grantDir.path)])
        ])
        XCTAssertFalse(accepted.isError, accepted.text)
        let draft = try XCTUnwrap(try fixture.proposalDraft())
        XCTAssertEqual(draft.workspaceKind, .project)
        XCTAssertEqual(draft.projectPath, "/tmp/other-project")
        XCTAssertEqual(draft.grantedRoots, [grantPath])
        XCTAssertTrue(accepted.text.contains("\"Other\" Project"), accepted.text)
        XCTAssertTrue(accepted.text.contains(grantPath), accepted.text)

        try fixture.deleteProposals()
        let refused = fixture.proposeWorkspace([
            "kind": .string("project"),
            "project_path": .string("/tmp/never-registered")
        ])
        XCTAssertTrue(refused.isError)
        XCTAssertTrue(refused.text.contains("not a Project in Alveary"), refused.text)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    func testCreateReplacesGrantsAndMayAddExistingFolders() throws {
        let grants = try makeGrantDirectories(count: 2)
        defer { try? FileManager.default.removeItem(at: grants.root) }
        let fixture = try ScheduledTaskHostToolFixture.task(
            descriptor: TaskWorkspaceDescriptor(
                primaryRoot: grants.workspace.path,
                grantedRoots: grants.paths,
                ownershipStrategy: .privateOwned,
                ownershipMarkerID: "private-marker"
            )
        )

        let narrowed = fixture.proposeWorkspace([
            "kind": .string("private"),
            "granted_roots": .array([.string(grants.paths[0])])
        ])
        XCTAssertFalse(narrowed.isError, narrowed.text)
        XCTAssertEqual(try XCTUnwrap(try fixture.proposalDraft()).grantedRoots, [grants.paths[0]])
        XCTAssertTrue(narrowed.text.contains(grants.paths[0]), narrowed.text)

        // A folder beyond the inherited set is accepted when it exists — the raw spelling here
        // is unnormalized on purpose, so the stored root is the canonical resolved path.
        let extra = grants.root.appendingPathComponent("Extra", isDirectory: true)
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        let extraPath = CanonicalPath.normalize(extra.path)
        try fixture.deleteProposals()
        let added = fixture.proposeWorkspace([
            "kind": .string("private"),
            "granted_roots": .array([.string(grants.paths[0]), .string(extra.path)])
        ])
        XCTAssertFalse(added.isError, added.text)
        XCTAssertEqual(try XCTUnwrap(try fixture.proposalDraft()).grantedRoots, [grants.paths[0], extraPath])
        XCTAssertTrue(added.text.contains(extraPath), added.text)

        try fixture.deleteProposals()
        for unusable in ["Grants/relative", "/tmp/never-granted-\(UUID().uuidString)"] {
            let refused = fixture.proposeWorkspace([
                "kind": .string("private"),
                "granted_roots": .array([.string(unusable)])
            ])
            XCTAssertTrue(refused.isError, refused.text)
            XCTAssertTrue(refused.text.contains("absolute path to an existing folder"), refused.text)
        }
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    func testEmptyGrantListDropsEveryInheritedGrant() throws {
        let grants = try makeGrantDirectories(count: 1)
        defer { try? FileManager.default.removeItem(at: grants.root) }
        let fixture = try ScheduledTaskHostToolFixture.task(
            descriptor: TaskWorkspaceDescriptor(
                primaryRoot: grants.workspace.path,
                grantedRoots: grants.paths,
                ownershipStrategy: .privateOwned,
                ownershipMarkerID: "private-marker"
            )
        )

        let result = fixture.proposeWorkspace([
            "kind": .string("private"),
            "granted_roots": .array([])
        ])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(try XCTUnwrap(try fixture.proposalDraft()).grantedRoots.isEmpty)
        XCTAssertTrue(result.text.contains("no folder grants"), result.text)
    }

    func testEditCanRetargetAnExistingDefinitionToAnotherThread() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let definition = fixture.insertDefinition(id: "retarget", revision: 2)
        try fixture.insertTargetThread(name: "Release chat", conversationID: "release-main")

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: [
                    "action": .string("edit"),
                    "task_id": .string(definition.id),
                    "revision": .number(2),
                    "changes": .object([
                        "destination": .string("existing_thread"),
                        "target_thread_id": .string("release-main")
                    ])
                ]
            )
        )

        XCTAssertFalse(result.isError, result.text)
        let draft = try XCTUnwrap(try fixture.proposalDraft())
        XCTAssertEqual(draft.destination, .existingThread)
        XCTAssertEqual(draft.targetConversationID, "release-main")
        XCTAssertEqual(draft.title, definition.title)
        // Nothing has changed yet — the proposal still awaits confirmation.
        XCTAssertEqual(definition.revision, 2)
    }

    /// The proposal's trusted Project has to be the one its draft names. `ScheduledTaskProposal`
    /// keeps the Project as a relationship so deletion nullifies it, and the queue coordinator
    /// refuses to confirm any proposal whose relationship disagrees with the draft's path.
    func testEditToAnotherProjectStoresThatProjectAsTheProposalsTrustedOne() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let definition = fixture.insertDefinition(id: "reproject", revision: 2)
        let target = Project(path: "/tmp/other-project", name: "Other")
        fixture.modelContext.insert(target)
        try fixture.modelContext.save()

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: [
                    "action": .string("edit"),
                    "task_id": .string(definition.id),
                    "revision": .number(2),
                    "changes": .object([
                        "workspace": .object([
                            "kind": .string("project"),
                            "project_path": .string("/tmp/other-project")
                        ])
                    ])
                ]
            )
        )

        XCTAssertFalse(result.isError, result.text)
        let proposal = try XCTUnwrap(
            try fixture.modelContext.fetch(FetchDescriptor<ScheduledTaskProposal>()).first
        )
        XCTAssertEqual(proposal.definitionDraft?.projectPath, "/tmp/other-project")
        XCTAssertEqual(proposal.project?.path, "/tmp/other-project")
        XCTAssertTrue(proposal.hasValidActionShape)
    }

    func testInheritedPlacementLeavesTheSourceWorkspaceUntouched() throws {
        let fixture = try ScheduledTaskHostToolFixture.project()

        let result = fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: createArguments()
            )
        )

        XCTAssertFalse(result.isError)
        let draft = try XCTUnwrap(try fixture.proposalDraft())
        // Creates without an explicit destination take the editor's reuse default.
        XCTAssertEqual(draft.destination, .reusedThread)
        XCTAssertEqual(draft.projectPath, fixture.project?.path)
        // No placement was requested, so the result stays the plain confirmation sentence.
        XCTAssertFalse(result.text.contains("It will"), result.text)
    }

    private func makeGrantDirectories(count: Int) throws -> ScheduledTaskHostToolGrantFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledTaskHostToolPlacement-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let paths = try (0 ..< count).map { index -> String in
            let grant = root.appendingPathComponent("Grant\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: grant, withIntermediateDirectories: true)
            return CanonicalPath.normalize(grant.path)
        }
        return ScheduledTaskHostToolGrantFixture(root: root, workspace: workspace, paths: paths)
    }
}

extension ScheduledTaskHostToolFixture {
    func proposalDraft() throws -> ScheduledTaskProposalDefinitionDraft? {
        try modelContext.fetch(FetchDescriptor<ScheduledTaskProposal>()).first?.definitionDraft
    }

    func deleteProposals() throws {
        for proposal in try modelContext.fetch(FetchDescriptor<ScheduledTaskProposal>()) {
            modelContext.delete(proposal)
        }
        try modelContext.save()
    }

    func proposeExistingThread(targetThreadID: String) -> AgentCLIKit.AgentHostToolResult {
        propose([
            "destination": .string("existing_thread"),
            "target_thread_id": .string(targetThreadID)
        ])
    }

    func proposeWorkspace(_ workspace: [String: AgentCLIKit.JSONValue]) -> AgentCLIKit.AgentHostToolResult {
        propose(["workspace": .object(workspace)])
    }

    private func propose(_ placement: [String: AgentCLIKit.JSONValue]) -> AgentCLIKit.AgentHostToolResult {
        var arguments: [String: AgentCLIKit.JSONValue] = [
            "action": .string("create"),
            "title": .string("Daily review"),
            "prompt": .string("Review the latest changes."),
            "schedule": .object([
                "kind": .string("daily"),
                "hour": .number(9),
                "minute": .number(15)
            ])
        ]
        arguments.merge(placement) { _, new in new }
        return service.handle(
            // A fresh request id per call, so a differing placement is not read as a retry.
            context: agentContext(requestID: "string:\(UUID().uuidString)"),
            call: AgentCLIKit.AgentHostToolCall(
                name: ScheduledTaskHostToolCatalog.proposeToolName,
                arguments: arguments
            )
        )
    }
}

private struct ScheduledTaskHostToolGrantFixture {
    let root: URL
    let workspace: URL
    let paths: [String]
}
