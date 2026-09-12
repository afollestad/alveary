import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskHostToolServiceTests {
    func testFolderDiscoverySaveFailurePreservesUnrelatedPendingEdits() async throws {
        let paths = try makeSymlinkGrantFixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fixture = try ScheduledTaskHostToolFixture.project()
        let unrelated = Project(name: "Original name")
        fixture.modelContext.insert(unrelated)
        try fixture.modelContext.save()
        var discoveryFinished = false
        let service = ScheduledTaskHostToolFixture.makeService(
            modelContext: fixture.modelContext, notificationCenter: fixture.notificationCenter,
            requestParser: ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "Etc/UTC"),
            resolveSourceFolder: { path in
                unrelated.name = "Pending rename"
                discoveryFinished = true
                return SourceFolderSnapshot(path: path)
            },
            saveChanges: { context in
                if discoveryFinished { throw NSError(domain: "InjectedSaveFailure", code: 1) }
                try context.save()
            }
        )
        var arguments = createArguments()
        arguments["workspace"] = .object([
            "kind": .string("private"), "granted_roots": .array([.string(paths.grant.path)])
        ])

        let result = await service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: arguments)
        )

        XCTAssertTrue(discoveryFinished)
        XCTAssertTrue(result.isError)
        XCTAssertEqual(unrelated.name, "Pending rename")
        XCTAssertTrue(fixture.modelContext.hasChanges)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    func testNewGrantCapturesGitMetadataWithoutRewritingInheritedFolder() async throws {
        let paths = try makeSymlinkGrantFixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fixture = try ScheduledTaskHostToolFixture.project()
        let retained = SourceFolderSnapshot(path: CanonicalPath.normalize(paths.workspace.path), gitBranch: "saved-branch")
        fixture.thread.workspaceSnapshot = WorkspaceSnapshot(primarySource: fixture.thread.sourceFolder, grants: [retained])
        try fixture.modelContext.save()
        let addedPath = CanonicalPath.normalize(paths.grant.path)
        let added = SourceFolderSnapshot(path: addedPath, gitRemote: "git@github.com:owner/repo.git", gitBranch: "main")
        var resolvedPaths: [String] = []
        let service = ScheduledTaskHostToolFixture.makeService(
            modelContext: fixture.modelContext, notificationCenter: fixture.notificationCenter,
            requestParser: ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "Etc/UTC"),
            resolveSourceFolder: { path in
                resolvedPaths.append(path)
                return added
            }
        )
        var arguments = createArguments()
        arguments["workspace"] = .object([
            "kind": .string("private"), "granted_roots": .array([.string(retained.path), .string(addedPath)])
        ])
        let result = await service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: arguments)
        )
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(resolvedPaths, [addedPath])
        XCTAssertEqual(try fixture.proposalDraft()?.workspaceSnapshot?.grants, [retained, added])
    }

    func testFolderDiscoveryRevalidatesCallerBeforeOpeningProposal() async throws {
        let paths = try makeSymlinkGrantFixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let fixture = try ScheduledTaskHostToolFixture.project()
        let service = ScheduledTaskHostToolFixture.makeService(
            modelContext: fixture.modelContext, notificationCenter: fixture.notificationCenter,
            requestParser: ScheduledTaskHostToolRequestParser(defaultTimeZoneIdentifier: "Etc/UTC"),
            resolveSourceFolder: { path in
                fixture.modelContext.delete(fixture.conversation)
                try? fixture.modelContext.save()
                return SourceFolderSnapshot(path: path, gitBranch: "main")
            }
        )
        var arguments = createArguments()
        arguments["workspace"] = .object([
            "kind": .string("private"), "granted_roots": .array([.string(paths.grant.path)])
        ])
        let result = await service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: arguments)
        )
        XCTAssertTrue(result.isError)
        XCTAssertEqual(try fixture.modelContext.fetchCount(FetchDescriptor<ScheduledTaskProposal>()), 0)
    }

    func testCreateRejectsTaskGrantWhoseCanonicalTargetChanged() async throws {
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

        let result = await fixture.service.handle(
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

    func testEditRejectsDefinitionGrantWhoseCanonicalTargetChanged() async throws {
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

        let result = await fixture.service.handle(
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

    func testExplicitProjectReplacesUnreadableCallerWorkspace() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let project = try XCTUnwrap(fixture.project)
        fixture.thread.workspaceSnapshotJSON = "invalid"
        try fixture.modelContext.save()

        let result = await fixture.proposeWorkspace([
            "kind": .string("project"), "project_id": .string(project.id)
        ])

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try fixture.proposalDraft()?.workspaceSnapshot, project.workspaceSnapshot())
    }

    func testExplicitGrantRemovalRepairsUnreadableWorkspaceWhileOmissionFails() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        fixture.thread.workspaceSnapshotJSON = "invalid"
        try fixture.modelContext.save()

        let inherited = await fixture.proposeWorkspace(["kind": .string("private")])
        XCTAssertTrue(inherited.isError)
        let replacement = await fixture.proposeWorkspace([
            "kind": .string("private"), "granted_roots": .array([])
        ])
        XCTAssertFalse(replacement.isError, replacement.text)
        let snapshot = try XCTUnwrap(try fixture.proposalDraft()?.workspaceSnapshot)
        XCTAssertNil(snapshot.primarySource)
        XCTAssertTrue(snapshot.grants.isEmpty)
        XCTAssertTrue(snapshot.rootsExplicitlyManaged)
    }

    func testExplicitProjectEditReplacesUnreadableDefinitionWorkspace() async throws {
        let fixture = try ScheduledTaskHostToolFixture.project()
        let project = try XCTUnwrap(fixture.project)
        let definition = fixture.insertDefinition(id: "repair")
        definition.workspaceSnapshotJSON = "invalid"
        try fixture.modelContext.save()
        let arguments = targetArguments(action: "edit", definitionID: definition.id, revision: 1).merging([
            "changes": .object(["workspace": .object([
                "kind": .string("project"), "project_id": .string(project.id)
            ])])
        ]) { _, new in new }

        let result = await fixture.service.handle(
            context: fixture.agentContext(),
            call: AgentCLIKit.AgentHostToolCall(name: ScheduledTaskHostToolCatalog.proposeToolName, arguments: arguments)
        )
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try fixture.proposalDraft()?.workspaceSnapshot, project.workspaceSnapshot())
        XCTAssertEqual(definition.workspaceSnapshotJSON, "invalid")
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
