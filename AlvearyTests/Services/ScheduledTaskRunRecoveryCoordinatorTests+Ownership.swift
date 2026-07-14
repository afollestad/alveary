import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunRecoveryCoordinatorTests {
    func testRecoveryInterruptsClaimWithMalformedWorkspaceKind() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 8_000_000)
        let run = fixture.insertRun(
            status: .claimed,
            occurrenceAt: actionDate.addingTimeInterval(-60),
            withThread: false
        )
        run.workspaceKindRawValueSnapshot = "malformed-kind"
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in true }

        XCTAssertTrue(result.resumedRunIDs.isEmpty)
        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(run.thread?.taskWorkspaceDescriptor)
    }

    func testRecoveryInterruptsClaimWithMalformedWorkspaceStrategy() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 9_000_000)
        let run = fixture.insertRun(
            status: .claimed,
            occurrenceAt: actionDate.addingTimeInterval(-60),
            withThread: false
        )
        run.workspaceStrategyRawValueSnapshot = "malformed-strategy"
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in true }

        XCTAssertTrue(result.resumedRunIDs.isEmpty)
        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(run.thread?.taskWorkspaceDescriptor)
    }

    func testRecoveryRejectsClaimWhenProjectRootBecomesSymlinkToSameDirectory() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let paths = try RecoverySymlinkPaths(prefix: "claimed-project")
        defer { paths.removeFiles() }
        let actionDate = Date(timeIntervalSinceReferenceDate: 6_000_000)
        let run = fixture.insertRun(
            status: .claimed,
            occurrenceAt: actionDate.addingTimeInterval(-60),
            withThread: false
        )
        run.workspaceKindRawValueSnapshot = ScheduledTaskWorkspaceKind.project.rawValue
        run.workspaceStrategyRawValueSnapshot = ScheduledTaskWorkspaceStrategy.localCheckout.rawValue
        run.projectPathSnapshot = paths.literal.path
        run.workspaceIdentitySnapshot = ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: ScheduledTaskRootIdentitySnapshot(
                path: paths.literal.path,
                identity: paths.identity
            ),
            grantedRoots: []
        )
        fixture.workspaceOwnershipService.setIdentity(paths.identity, at: paths.literal.path)
        try fixture.context.save()
        try paths.replaceLiteralWithSymlinkToMovedDirectory()
        try paths.assertSymlinkTargetsOriginalDirectory()

        let result = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in true }

        XCTAssertTrue(result.resumedRunIDs.isEmpty)
        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(run.thread?.taskWorkspaceDescriptor)
    }

    func testRecoveryWithholdsExistingWorkspaceWhenGrantBecomesSymlinkToSameDirectory() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let paths = try RecoverySymlinkPaths(prefix: "existing-grant")
        defer { paths.removeFiles() }
        let actionDate = Date(timeIntervalSinceReferenceDate: 7_000_000)
        let markerID = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        let ownedRoot = paths.root.appendingPathComponent(markerID, isDirectory: true)
        try FileManager.default.createDirectory(at: ownedRoot, withIntermediateDirectories: false)
        let workspace = TaskWorkspaceDescriptor(
            primaryRoot: ownedRoot.path,
            grantedRoots: [paths.literal.path],
            ownershipStrategy: .privateOwned,
            ownershipMarkerID: markerID
        )
        let run = fixture.insertRun(status: .running, occurrenceAt: actionDate)
        run.grantedRootsSnapshot = [paths.literal.path]
        run.workspaceIdentitySnapshot = ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: nil,
            grantedRoots: [ScheduledTaskRootIdentitySnapshot(
                path: paths.literal.path,
                identity: paths.identity
            )]
        )
        run.preparedWorkspaceRoot = ownedRoot.path
        run.preparedWorkspaceOwnershipStrategy = .privateOwned
        run.preparedWorkspaceMarkerID = markerID
        run.thread?.taskWorkspaceDescriptor = workspace
        fixture.workspaceOwnershipService.setIdentity(paths.identity, at: paths.literal.path)
        fixture.workspaceOwnershipService.allow(workspace)
        try fixture.context.save()
        try paths.replaceLiteralWithSymlinkToMovedDirectory()
        try paths.assertSymlinkTargetsOriginalDirectory()

        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(run.thread?.taskWorkspaceDescriptor)
        XCTAssertNil(run.thread?.worktreePath)
        XCTAssertFalse(run.thread?.useWorktree == true)
    }
}

extension RecoveryWorkspaceOwnershipService {
    func registerOwnedWorktree(
        at path: String,
        sourceProjectPath: String,
        grantedRoots: [String],
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity,
        expectedSourceProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) throws -> TaskWorkspaceDescriptor {
        throw TaskWorkspaceOwnershipError.workspaceNotOwned
    }
}

private struct RecoverySymlinkPaths {
    let root: URL
    let literal: URL
    let moved: URL
    let identity: TaskWorkspaceFileSystemIdentity

    init(prefix: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "alveary-recovery-\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        literal = root.appendingPathComponent("Literal", isDirectory: true)
        moved = root.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: literal, withIntermediateDirectories: true)
        identity = try Self.directoryIdentity(at: literal.path)
    }

    func replaceLiteralWithSymlinkToMovedDirectory() throws {
        try FileManager.default.moveItem(at: literal, to: moved)
        try FileManager.default.createSymbolicLink(at: literal, withDestinationURL: moved)
    }

    func assertSymlinkTargetsOriginalDirectory(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertNotEqual(CanonicalPath.normalize(literal.path), literal.path, file: file, line: line)
        XCTAssertEqual(try Self.directoryIdentity(at: moved.path), identity, file: file, line: line)
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func directoryIdentity(at path: String) throws -> TaskWorkspaceFileSystemIdentity {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return TaskWorkspaceFileSystemIdentity(
            systemNumber: try XCTUnwrap(attributes[.systemNumber] as? NSNumber).uint64Value,
            fileNumber: try XCTUnwrap(attributes[.systemFileNumber] as? NSNumber).uint64Value
        )
    }
}
