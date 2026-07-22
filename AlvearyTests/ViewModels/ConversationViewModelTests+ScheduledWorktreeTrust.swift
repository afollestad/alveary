import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testLinkedProjectScheduledRunWithFallbackModeUsesProjectAutoTrust() throws {
        let fixture = try ConversationViewModelTestFixture(
            threadMode: .project,
            autoTrustProjects: true
        )
        let run = ScheduledTaskRun(
            occurrenceID: "fallback-trust-occurrence",
            definitionID: "fallback-trust-definition",
            definitionRevision: 1,
            occurrenceAt: .now,
            triggerKind: .scheduled,
            status: .preparing,
            titleSnapshot: "Fallback scheduled task",
            promptSnapshot: "Run it.",
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "claude",
            effortSnapshot: "high",
            permissionModeSnapshot: "acceptEdits",
            workspaceKindSnapshot: .project,
            workspaceStrategySnapshot: .worktree,
            thread: fixture.thread
        )
        fixture.thread.modeRawValue = "future-mode"
        fixture.context.insert(run)
        try fixture.context.save()

        XCTAssertEqual(fixture.thread.effectiveMode, .project)
        XCTAssertTrue(fixture.viewModel.shouldAutoTrustWorkspace(fixture.project.path))
    }

    func testAutomatedScheduledOwnedWorktreeIsTrustedAfterValidation() async throws {
        let scheduledFixture = try ScheduledWorktreeViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture

        try await fixture.viewModel.startAutomatedScheduledTurn("Run in the owned worktree.")

        let setupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(
            setupCalls,
            [
                .init(
                    providerId: "claude",
                    workingDirectory: scheduledFixture.descriptor.primaryRoot,
                    autoTrust: true
                )
            ]
        )
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 1)
    }

    func testAutomatedScheduledOwnedWorktreeIsRevalidatedAfterProviderSetup() async throws {
        let scheduledFixture = try ScheduledWorktreeViewModelFixture()
        defer { scheduledFixture.removeFiles() }
        let fixture = scheduledFixture.fixture
        let worktreePath = scheduledFixture.worktree.path
        await fixture.providerSetup.setPrepareForSpawnHook {
            try? FileManager.default.removeItem(atPath: worktreePath)
            try? FileManager.default.createDirectory(
                atPath: worktreePath,
                withIntermediateDirectories: true
            )
        }

        do {
            try await fixture.viewModel.startAutomatedScheduledTurn("Catch the owned-worktree swap.")
            XCTFail("Expected scheduled workspace validation to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                TaskWorkspaceOwnershipError.workspaceIdentityMismatch(worktreePath).localizedDescription
            )
        }

        let setupCalls = await fixture.providerSetup.calls()
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(setupCalls.count, 1)
        XCTAssertTrue(setupCalls[0].autoTrust)
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
    }
}

@MainActor
private struct ScheduledWorktreeViewModelFixture {
    let root: URL
    let worktree: URL
    let descriptor: TaskWorkspaceDescriptor
    let fixture: ConversationViewModelTestFixture

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScheduledWorktreeViewModelFixture-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceProject = root.appendingPathComponent("SourceProject", isDirectory: true)
        let worktree = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        let ownershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("WorktreeRecords", isDirectory: true)
        )
        let descriptor = try ownershipService.registerOwnedWorktree(
            at: worktree.path,
            sourceProjectPath: sourceProject.path,
            grantedRoots: []
        )
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            providerId: "claude",
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: ownershipService
        )
        let run = try Self.makeRun(
            fixture: fixture,
            descriptor: descriptor,
            sourceProject: sourceProject,
            ownershipService: ownershipService
        )
        fixture.context.insert(run)
        try fixture.context.save()
        self.root = root
        self.worktree = worktree
        self.descriptor = descriptor
        self.fixture = fixture
    }

    private static func makeRun(
        fixture: ConversationViewModelTestFixture,
        descriptor: TaskWorkspaceDescriptor,
        sourceProject: URL,
        ownershipService: DefaultTaskWorkspaceOwnershipService
    ) throws -> ScheduledTaskRun {
        let workspaceIdentities = try ScheduledTaskWorkspaceIdentitySnapshot(
            workspaceKind: .project,
            projectPath: sourceProject.path,
            grantedRootPaths: [],
            identityAtPath: ownershipService.directoryIdentity(at:)
        )
        let run = ScheduledTaskRun(
            occurrenceID: "scheduled-worktree-view-model-occurrence",
            definitionID: "scheduled-worktree-view-model-definition",
            definitionRevision: 1,
            occurrenceAt: .now,
            triggerKind: .scheduled,
            status: .preparing,
            titleSnapshot: "Scheduled worktree task",
            promptSnapshot: "Run it.",
            timeZoneIdentifierSnapshot: "America/Chicago",
            providerIDSnapshot: "claude",
            effortSnapshot: "high",
            permissionModeSnapshot: "acceptEdits",
            workspaceKindSnapshot: .project,
            workspaceStrategySnapshot: .worktree,
            projectPathSnapshot: sourceProject.path,
            grantedRootsSnapshot: [],
            workspaceIdentitySnapshot: workspaceIdentities,
            thread: fixture.thread
        )
        run.preparedWorkspaceRoot = descriptor.primaryRoot
        run.preparedWorkspaceOwnershipStrategy = descriptor.ownershipStrategy
        run.preparedWorkspaceMarkerID = descriptor.ownershipMarkerID
        return run
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}
