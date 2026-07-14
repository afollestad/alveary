import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunMaterializerTests {
    func testPrivateGrantValidationCleanupFailureRetainsWorkspaceForDeletion() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let grant = try fixture.createDirectory(named: "FailedCleanupGrant")
        let replacement = try fixture.createDirectory(named: "FailedCleanupReplacement")
        let ownershipService = ScheduledMaterializerOwnershipService(
            base: fixture.workspaceOwnershipService,
            removalError: ScheduledMaterializerTestError.cleanupFailed
        )
        let run = try fixture.insertRun(
            id: "private-grant-cleanup-failure",
            occurrenceID: "private-grant-cleanup-failure-occurrence",
            grantedRoots: [grant.path]
        )
        try FileManager.default.removeItem(at: grant)
        try FileManager.default.createSymbolicLink(
            atPath: grant.path,
            withDestinationPath: replacement.path
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer(
                ownershipService: ownershipService
            ).materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let workspace = try XCTUnwrap(persistedRun.thread?.taskWorkspaceDescriptor)
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertTrue(try XCTUnwrap(persistedRun.lastError).contains("workspace cleanup also failed"))
        XCTAssertEqual(workspace.ownershipStrategy, .privateOwned)
        XCTAssertEqual(persistedRun.preparedWorkspaceRoot, workspace.primaryRoot)
        XCTAssertEqual(persistedRun.preparedWorkspaceMarkerID, workspace.ownershipMarkerID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.primaryRoot))
    }
}
