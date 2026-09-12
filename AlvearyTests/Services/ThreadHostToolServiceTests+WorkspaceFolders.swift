import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ThreadHostToolServiceTests {
    func testFolderDiscoverySaveFailurePreservesUnrelatedPendingEdits() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let unrelated = Project(name: "Original name")
        var discoveryFinished = false
        let fixture = try ThreadHostToolFixture(
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
        fixture.modelContext.insert(unrelated)
        try fixture.modelContext.save()

        let result = await fixture.create(arguments: [
            "granted_roots": .array([.string(root.path)]), "initial_prompt": .string("Inspect the granted folder.")
        ])

        XCTAssertTrue(discoveryFinished)
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, ThreadHostToolServiceError.persistenceFailure.localizedDescription)
        XCTAssertEqual(unrelated.name, "Pending rename")
        XCTAssertTrue(fixture.modelContext.hasChanges)
        XCTAssertEqual(try fixture.threadCount(), 1)
        XCTAssertTrue(fixture.startedPrompts.prompts.isEmpty)
    }

    func testNewGrantStoresRepositoryMetadataAtExactGrantedSubdirectory() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let subdirectory = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let grant = SourceFolderSnapshot(
            path: CanonicalPath.normalize(subdirectory.path), gitRemote: "git@github.com:owner/repo.git", gitBranch: "main"
        )
        var resolvedPaths: [String] = []
        let fixture = try ThreadHostToolFixture(resolveSourceFolder: { path in
            resolvedPaths.append(path)
            return grant
        })
        let savedSource = try XCTUnwrap(fixture.thread.sourceFolder)
        let result = await fixture.create(arguments: [
            "granted_roots": .array([.string(savedSource.path), .string(subdirectory.path)])
        ])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(resolvedPaths, [grant.path])
        let thread = try fixture.createdThread(in: result)
        XCTAssertEqual(thread.sourceFolder, savedSource)
        XCTAssertEqual(thread.workspaceSnapshot?.grants, [savedSource, grant])
    }

    func testGrantDiscoveryPreservesInheritedPlacementFallbackAndExplicitPlacementFailure() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cases: [(mode: String?, section: String?)] = [(nil, nil), ("task", nil), (nil, "Research")]
        for placement in cases {
            let entered = expectation(description: "Metadata discovery started")
            let gate = MockShellRunnerGate()
            let fixture = try ThreadHostToolFixture(resolveSourceFolder: { path in
                entered.fulfill()
                await gate.wait()
                return SourceFolderSnapshot(path: path, gitBranch: "main")
            })
            try await fixture.moveSourceTaskIntoSection(named: "Research")
            let sectionID = try XCTUnwrap(fixture.thread.customSection?.id)
            var arguments: [String: AgentCLIKit.JSONValue] = ["granted_roots": .array([.string(root.path)])]
            if let mode = placement.mode { arguments["mode"] = .string(mode) }
            if let section = placement.section { arguments["section"] = .string(section) }
            let capturedArguments = arguments
            let creation = Task { await fixture.create(arguments: capturedArguments) }
            defer {
                gate.open()
                creation.cancel()
            }
            await fulfillment(of: [entered], timeout: 2)
            _ = try fixture.service.sectionService.removeSection(id: sectionID)
            gate.open()
            let result = await creation.value
            if placement.section != nil {
                XCTAssertTrue(result.isError, result.text)
                XCTAssertEqual(try fixture.threadCount(), 1)
            } else {
                XCTAssertFalse(result.isError, result.text)
                let created = try fixture.createdThread(in: result)
                XCTAssertNil(created.customSection)
                XCTAssertEqual(created.workspaceSnapshot?.grants.map(\.path), [CanonicalPath.normalize(root.path)])
            }
        }
    }

    func testExplicitProjectCanChooseASecondaryPrimaryAndClearItsGrants() async throws {
        let fixture = try ThreadHostToolFixture()
        let secondary = try addHostSourceFolder(to: fixture)
        let result = await fixture.create(arguments: [
            "project_id": .string(fixture.project.id), "primary_folder_path": .string(secondary.path),
            "granted_roots": .array([])
        ])
        XCTAssertFalse(result.isError, result.text)
        let thread = try fixture.createdThread(in: result)
        XCTAssertEqual(thread.sourceFolder, secondary)
        XCTAssertEqual(thread.project?.id, fixture.project.id)
        XCTAssertEqual(thread.workspaceSnapshot?.additionalWorkspaceRoots(workingDirectory: secondary.path), [secondary.path])
        XCTAssertFalse(thread.useWorktree)
    }

    func testOmittedProjectInheritsSavedFoldersAfterProjectDefaultsChange() async throws {
        let fixture = try ThreadHostToolFixture()
        let saved = fixture.thread.workspaceSnapshot
        let secondary = try addHostSourceFolder(to: fixture)
        fixture.project.primaryFolderID = fixture.project.orderedFolders.last?.id
        try fixture.modelContext.save()

        let inherited = await fixture.create(arguments: ["name": .string("Inherited")])
        XCTAssertFalse(inherited.isError, inherited.text)
        XCTAssertEqual(try fixture.createdThread(in: inherited).workspaceSnapshot, saved)

        let explicit = await fixture.create(arguments: ["project_id": .string(fixture.project.id)])
        XCTAssertFalse(explicit.isError, explicit.text)
        let thread = try fixture.createdThread(in: explicit)
        XCTAssertEqual(thread.sourceFolder, secondary)
        XCTAssertEqual(thread.workspaceSnapshot?.grants.map(\.path), saved?.sourceFolders.map(\.path))
    }

    func testEmptyProjectCreatesAPrivateWorkspaceUnderItsStableIdentity() async throws {
        let fixture = try ThreadHostToolFixture()
        let empty = Project(name: "Empty", folders: [])
        fixture.modelContext.insert(empty)
        try fixture.modelContext.save()
        let result = await fixture.create(arguments: ["project_id": .string(empty.id)])
        XCTAssertFalse(result.isError, result.text)
        let thread = try fixture.createdThread(in: result)
        XCTAssertEqual(thread.project?.id, empty.id)
        XCTAssertNil(thread.sourceFolder)
        XCTAssertEqual(thread.taskWorkspaceDescriptor?.ownershipStrategy, .privateOwned)
        XCTAssertEqual(thread.workspaceSnapshot?.rootsExplicitlyManaged, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(thread.primaryWorkingDirectory)))
    }

    func testSharedLegacyPathIsRefusedButProjectIDRemainsUnambiguous() async throws {
        let fixture = try ThreadHostToolFixture()
        let shared = Project(name: "Shared", folders: fixture.project.orderedFolders.map(\.snapshot))
        fixture.modelContext.insert(shared)
        try fixture.modelContext.save()
        let ambiguous = await fixture.create(arguments: ["project_path": .string(fixture.project.path)])
        XCTAssertTrue(ambiguous.isError)
        XCTAssertEqual(try fixture.threadCount(), 1)
        let selected = await fixture.create(arguments: ["project_id": .string(shared.id)])
        XCTAssertFalse(selected.isError, selected.text)
        XCTAssertEqual(try fixture.createdThread(in: selected).project?.id, shared.id)
    }

    func testRetryReplaysOriginalFolderReceiptAfterProjectEdits() async throws {
        let fixture = try ThreadHostToolFixture()
        let arguments: [String: AgentCLIKit.JSONValue] = ["project_id": .string(fixture.project.id)]
        let first = await fixture.create(arguments: arguments)
        XCTAssertFalse(first.isError, first.text)
        _ = try addHostSourceFolder(to: fixture)
        fixture.project.primaryFolderID = fixture.project.orderedFolders.last?.id
        fixture.project.name = "Renamed"
        try fixture.modelContext.save()
        let retry = await fixture.create(arguments: arguments)
        XCTAssertEqual(retry.structuredContent, first.structuredContent)
        XCTAssertEqual(retry.text, first.text)
        XCTAssertEqual(try fixture.threadCount(), 2)
    }

    private func addHostSourceFolder(to fixture: ThreadHostToolFixture) throws -> SourceFolderSnapshot {
        let url = fixture.directory.appendingPathComponent("secondary")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let source = SourceFolderSnapshot(path: CanonicalPath.normalize(url.path))
        let membership = ProjectFolder(snapshot: source, sortOrder: fixture.project.folders.count)
        membership.project = fixture.project
        fixture.project.folders.append(membership)
        fixture.modelContext.insert(membership)
        try fixture.modelContext.save()
        return source
    }
}
