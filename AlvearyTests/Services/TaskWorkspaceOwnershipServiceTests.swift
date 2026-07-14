import XCTest

@testable import Alveary

final class TaskWorkspaceOwnershipServiceTests: XCTestCase {
    private var fixtureRoot: URL!
    private var privateRoot: URL!
    private var worktreeRecordsRoot: URL!
    private var service: DefaultTaskWorkspaceOwnershipService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskWorkspaceOwnershipServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        privateRoot = fixtureRoot.appendingPathComponent("Private", isDirectory: true)
        worktreeRecordsRoot = fixtureRoot.appendingPathComponent("WorktreeOwnership", isDirectory: true)
        service = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: privateRoot,
            worktreeOwnershipRecordsRoot: worktreeRecordsRoot
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
        service = nil
        worktreeRecordsRoot = nil
        privateRoot = nil
        fixtureRoot = nil
        try super.tearDownWithError()
    }

    func testCreateValidateAndRemovePrivateWorkspace() throws {
        let descriptor = try service.createPrivateWorkspace()

        XCTAssertEqual(descriptor.ownershipStrategy, .privateOwned)
        XCTAssertNotNil(descriptor.ownershipMarkerID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: descriptor.primaryRoot))
        XCTAssertNoThrow(try service.validateOwnedWorkspace(descriptor))

        try service.removeOwnedWorkspace(descriptor)

        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptor.primaryRoot))
        XCTAssertThrowsError(try service.validateOwnedWorkspace(descriptor)) { error in
            guard case TaskWorkspaceOwnershipError.missingDirectory = error else {
                return XCTFail("Expected a missing-directory error, got \(error)")
            }
        }
        XCTAssertNoThrow(try service.removeOwnedWorkspace(descriptor))
    }

    func testRemoveMissingPrivateWorkspaceIsIdempotentWhenControlRootIsAlsoMissing() throws {
        let descriptor = try service.createPrivateWorkspace()
        try FileManager.default.removeItem(at: privateRoot)

        XCTAssertNoThrow(try service.removeOwnedWorkspace(descriptor))
    }

    func testOrphanSweepPreservesRetainedPrivateWorkspace() throws {
        let retained = try service.createPrivateWorkspace()
        let orphaned = try service.createPrivateWorkspace()

        try service.removeOrphanedPrivateWorkspaces(
            retainingMarkerIDs: [try XCTUnwrap(retained.ownershipMarkerID)]
        )

        XCTAssertNoThrow(try service.validateOwnedWorkspace(retained))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphaned.primaryRoot))
    }

    func testPrivateWorkspaceOutsideOwnedRootIsNeverRemoved() throws {
        let ownedDescriptor = try service.createPrivateWorkspace()
        let outsideRoot = fixtureRoot.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        let forgedDescriptor = TaskWorkspaceDescriptor(
            primaryRoot: outsideRoot.path,
            ownershipStrategy: .privateOwned,
            ownershipMarkerID: ownedDescriptor.ownershipMarkerID
        )

        XCTAssertThrowsError(try service.removeOwnedWorkspace(forgedDescriptor)) { error in
            guard case TaskWorkspaceOwnershipError.outsideOwnedRoot = error else {
                return XCTFail("Expected an outside-owned-root error, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideRoot.path))
    }

    func testPrivateWorkspaceMarkerMismatchIsNeverRemoved() throws {
        let descriptor = try service.createPrivateWorkspace()
        let markerURL = URL(fileURLWithPath: descriptor.primaryRoot, isDirectory: true)
            .appendingPathComponent(".alveary-task-workspace.json")
        try Data("{}".utf8).write(to: markerURL, options: [.atomic])

        XCTAssertThrowsError(try service.removeOwnedWorkspace(descriptor)) { error in
            guard case TaskWorkspaceOwnershipError.ownershipMarkerMismatch = error else {
                return XCTFail("Expected a marker-mismatch error, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: descriptor.primaryRoot))
    }

    func testReplacingPrivateWorkspaceWithSymlinkNeverRemovesTarget() throws {
        let descriptor = try service.createPrivateWorkspace()
        let targetURL = fixtureRoot.appendingPathComponent("SymlinkTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.removeItem(atPath: descriptor.primaryRoot)
        try FileManager.default.createSymbolicLink(atPath: descriptor.primaryRoot, withDestinationPath: targetURL.path)

        XCTAssertThrowsError(try service.removeOwnedWorkspace(descriptor))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.path))
    }

    func testReplacingConfiguredPrivateRootWithSymlinkPreventsCreationOutsideIt() throws {
        let targetURL = fixtureRoot.appendingPathComponent("UnexpectedTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: privateRoot.path, withDestinationPath: targetURL.path)

        XCTAssertThrowsError(try service.createPrivateWorkspace()) { error in
            guard case TaskWorkspaceOwnershipError.symbolicLink = error else {
                return XCTFail("Expected a symbolic-link error, got \(error)")
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: targetURL.path), [])
    }

    func testCanonicalizeGrantsResolvesAliasesDeduplicatesAndExcludesPrimaryRoot() throws {
        let primaryRoot = fixtureRoot.appendingPathComponent("Primary", isDirectory: true)
        let grantedRoot = fixtureRoot.appendingPathComponent("Granted", isDirectory: true)
        let grantedAlias = fixtureRoot.appendingPathComponent("GrantedAlias", isDirectory: true)
        try FileManager.default.createDirectory(at: primaryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: grantedRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: grantedAlias.path, withDestinationPath: grantedRoot.path)

        let result = try service.canonicalizeGrants(
            [grantedAlias.path, grantedRoot.path, primaryRoot.path],
            excludingPrimaryRoot: primaryRoot.path
        )

        XCTAssertEqual(result, [CanonicalPath.normalize(grantedRoot.path)])
    }

    func testCanonicalizeGrantsRejectsRelativeAndMissingDirectories() {
        XCTAssertThrowsError(try service.canonicalizeGrants(["relative/path"], excludingPrimaryRoot: nil))
        XCTAssertThrowsError(
            try service.canonicalizeGrants(
                [fixtureRoot.appendingPathComponent("Missing").path],
                excludingPrimaryRoot: nil
            )
        )
    }

    func testRegisterValidateAndRemoveOwnedWorktree() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("Worktree", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        let descriptor = try service.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )

        XCTAssertEqual(descriptor.ownershipStrategy, .projectWorktreeOwned)
        XCTAssertEqual(descriptor.sourceProjectPath, CanonicalPath.normalize(sourceRoot.path))
        XCTAssertEqual(
            try service.sourceProjectIdentity(forOwnedWorktree: descriptor),
            try service.directoryIdentity(at: sourceRoot.path)
        )
        XCTAssertNoThrow(try service.validateOwnedWorkspace(descriptor))

        try service.removeOwnedWorkspace(descriptor)

        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptor.primaryRoot))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: worktreeRecordsRoot.path), [])
    }

    func testRegisterOwnedWorktreeRejectsSymlinkRoot() throws {
        let worktreeTarget = fixtureRoot.appendingPathComponent("WorktreeTarget", isDirectory: true)
        let worktreeAlias = fixtureRoot.appendingPathComponent("WorktreeAlias", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeTarget, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: worktreeAlias.path, withDestinationPath: worktreeTarget.path)

        XCTAssertThrowsError(
            try service.registerOwnedWorktree(
                at: worktreeAlias.path,
                sourceProjectPath: fixtureRoot.path,
                grantedRoots: []
            )
        ) { error in
            guard case TaskWorkspaceOwnershipError.symbolicLink = error else {
                return XCTFail("Expected a symbolic-link error, got \(error)")
            }
        }
    }

    func testIdentityAwareRegistrationRejectsReplacementWithoutCreatingSidecar() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("IdentityWorktree", isDirectory: true)
        let movedWorktreeRoot = fixtureRoot.appendingPathComponent("MovedIdentityWorktree", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("IdentitySource", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let worktreeIdentity = try service.directoryIdentity(at: worktreeRoot.path)
        let sourceIdentity = try service.directoryIdentity(at: sourceRoot.path)
        try FileManager.default.moveItem(at: worktreeRoot, to: movedWorktreeRoot)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        let sentinel = worktreeRoot.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)

        XCTAssertThrowsError(
            try service.registerOwnedWorktree(
                at: worktreeRoot.path,
                sourceProjectPath: sourceRoot.path,
                grantedRoots: [],
                expectedWorktreeIdentity: worktreeIdentity,
                expectedSourceProjectIdentity: sourceIdentity
            )
        ) { error in
            XCTAssertEqual(
                error as? TaskWorkspaceOwnershipError,
                .workspaceIdentityMismatch(worktreeRoot.path)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRecordsRoot.path))
    }

    func testRemoveOwnedWorktreeClearsSidecarAfterGitAlreadyRemovedDirectory() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("Worktree", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let descriptor = try service.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        try service.validateOwnedWorkspace(descriptor)
        try FileManager.default.removeItem(at: worktreeRoot)

        try service.removeOwnedWorkspace(descriptor)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: worktreeRecordsRoot.path), [])
    }

    func testRemoveOwnedWorktreeIsIdempotentAfterDirectoryAndSidecarAreGone() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("Worktree", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let descriptor = try service.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )

        try service.removeOwnedWorkspace(descriptor)

        XCTAssertNoThrow(try service.removeOwnedWorkspace(descriptor))
        XCTAssertNil(try service.ownedWorktreeIdentity(for: descriptor))
    }

    func testCompletedOwnedWorktreeRemovalRejectsMalformedDescriptor() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("Worktree", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let descriptor = try service.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        try service.removeOwnedWorkspace(descriptor)
        let noncanonicalDescriptor = TaskWorkspaceDescriptor(
            persistedPrimaryRoot: worktreeRoot.path + "/../Worktree",
            persistedGrantedRoots: [],
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: descriptor.ownershipMarkerID,
            persistedSourceProjectPath: descriptor.sourceProjectPath
        )
        let missingSourceDescriptor = TaskWorkspaceDescriptor(
            persistedPrimaryRoot: descriptor.primaryRoot,
            persistedGrantedRoots: [],
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: descriptor.ownershipMarkerID,
            persistedSourceProjectPath: nil
        )
        let noncanonicalSourceDescriptor = TaskWorkspaceDescriptor(
            persistedPrimaryRoot: descriptor.primaryRoot,
            persistedGrantedRoots: [],
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: descriptor.ownershipMarkerID,
            persistedSourceProjectPath: sourceRoot.path + "/../Source"
        )

        XCTAssertThrowsError(try service.removeOwnedWorkspace(noncanonicalDescriptor))
        XCTAssertThrowsError(try service.ownedWorktreeIdentity(for: noncanonicalDescriptor))
        XCTAssertThrowsError(try service.removeOwnedWorkspace(missingSourceDescriptor))
        XCTAssertThrowsError(try service.ownedWorktreeIdentity(for: missingSourceDescriptor))
        XCTAssertThrowsError(try service.removeOwnedWorkspace(noncanonicalSourceDescriptor))
        XCTAssertThrowsError(try service.ownedWorktreeIdentity(for: noncanonicalSourceDescriptor))
    }

    func testRemoveOwnedWorktreeRejectsReplacementWhenSidecarIsGone() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("Worktree", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let descriptor = try service.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        try service.removeOwnedWorkspace(descriptor)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        let sentinelURL = worktreeRoot.appendingPathComponent("keep.txt")
        try Data("user data".utf8).write(to: sentinelURL)

        XCTAssertThrowsError(try service.removeOwnedWorkspace(descriptor)) { error in
            guard case TaskWorkspaceOwnershipError.missingOwnershipMarker = error else {
                return XCTFail("Expected a missing-ownership-marker error, got \(error)")
            }
        }
        XCTAssertThrowsError(try service.ownedWorktreeIdentity(for: descriptor))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinelURL.path))
    }

    func testRemoveOwnedWorktreePreservesReplacementDirectoryAtSamePath() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("Worktree", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let descriptor = try service.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        try FileManager.default.removeItem(at: worktreeRoot)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        let sentinelURL = worktreeRoot.appendingPathComponent("keep.txt")
        try Data("user data".utf8).write(to: sentinelURL)

        XCTAssertThrowsError(try service.removeOwnedWorkspace(descriptor)) { error in
            guard case TaskWorkspaceOwnershipError.workspaceIdentityMismatch = error else {
                return XCTFail("Expected an identity-mismatch error, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinelURL.path))

        try service.discardOwnedWorktreeRecord(descriptor)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: worktreeRecordsRoot.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinelURL.path))
    }

}

extension TaskWorkspaceOwnershipServiceTests {
    func testBrokenWorktreeSymlinkNeverDiscardsOwnershipProof() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("BrokenWorktreeLink", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("BrokenWorktreeSource", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let descriptor = try service.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        try FileManager.default.removeItem(at: worktreeRoot)
        let missingTarget = fixtureRoot.appendingPathComponent("MissingTarget", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            atPath: worktreeRoot.path,
            withDestinationPath: missingTarget.path
        )

        XCTAssertThrowsError(try service.removeOwnedWorkspace(descriptor))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: worktreeRoot.path),
            missingTarget.path
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: worktreeRecordsRoot.path).count, 1)
    }

    func testProvisionalWorktreeWithoutSidecarIsRemovedOnlyWithMatchingIdentity() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("ProvisionalWorktree", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("ProvisionalSource", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let identity = try service.directoryIdentity(at: worktreeRoot.path)
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: worktreeRoot.path,
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: UUID().uuidString.lowercased(),
            sourceProjectPath: sourceRoot.path
        )

        try service.removeProvisionalOwnedWorktree(
            descriptor,
            expectedWorktreeIdentity: identity
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
    }

    func testProvisionalWorktreePreservesSamePathReplacement() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("ProvisionalReplacement", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("ProvisionalReplacementSource", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let originalIdentity = try service.directoryIdentity(at: worktreeRoot.path)
        try FileManager.default.removeItem(at: worktreeRoot)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        let sentinel = worktreeRoot.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: worktreeRoot.path,
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: UUID().uuidString.lowercased(),
            sourceProjectPath: sourceRoot.path
        )

        XCTAssertThrowsError(try service.removeProvisionalOwnedWorktree(
            descriptor,
            expectedWorktreeIdentity: originalIdentity
        )) { error in
            guard case TaskWorkspaceOwnershipError.workspaceIdentityMismatch = error else {
                return XCTFail("Expected an identity mismatch, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

}

extension TaskWorkspaceOwnershipServiceTests {
    func testOwnedWorktreeRejectsTamperedSourceProjectPath() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("Worktree", isDirectory: true)
        let sourceRoot = fixtureRoot.appendingPathComponent("Source", isDirectory: true)
        let otherSourceRoot = fixtureRoot.appendingPathComponent("OtherSource", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherSourceRoot, withIntermediateDirectories: true)
        let descriptor = try service.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceRoot.path,
            grantedRoots: []
        )
        let tamperedDescriptor = TaskWorkspaceDescriptor(
            primaryRoot: descriptor.primaryRoot,
            ownershipStrategy: descriptor.ownershipStrategy,
            ownershipMarkerID: descriptor.ownershipMarkerID,
            sourceProjectPath: otherSourceRoot.path
        )

        XCTAssertThrowsError(try service.removeOwnedWorkspace(tamperedDescriptor)) { error in
            guard case TaskWorkspaceOwnershipError.ownershipMarkerMismatch = error else {
                return XCTFail("Expected a marker-mismatch error, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreeRoot.path))
    }

    func testProjectLocalWorkspaceIsNeverRemoved() throws {
        let localRoot = fixtureRoot.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: localRoot, withIntermediateDirectories: true)
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: localRoot.path,
            ownershipStrategy: .projectLocal,
            sourceProjectPath: localRoot.path
        )

        XCTAssertThrowsError(try service.removeOwnedWorkspace(descriptor)) { error in
            XCTAssertEqual(error as? TaskWorkspaceOwnershipError, .workspaceNotOwned)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: localRoot.path))
    }

    func testWorktreeMarkerIDCannotTraverseSidecarRoot() throws {
        let worktreeRoot = fixtureRoot.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: worktreeRoot.path,
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: "../../outside"
        )

        XCTAssertThrowsError(try service.validateOwnedWorkspace(descriptor))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreeRoot.path))
    }
}
