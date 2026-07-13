import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testProjectlessTaskSetupUsesPrimaryWorkspaceAndProviderNeutralGrants() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            providerId: "codex",
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            autoTrustProjects: false,
            taskWorkspaceOwnershipService: environment.service
        )

        try await fixture.viewModel.setupAndStart("Run the task")

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let createCalls = await fixture.worktreeManager.createCalls()
        let providerSetupCalls = await fixture.providerSetup.calls()
        let spawnCall = try XCTUnwrap(spawnCalls.first)
        XCTAssertNil(try fixture.dbThread().project)
        XCTAssertEqual(spawnCall.config.workingDirectory, descriptor.primaryRoot)
        XCTAssertEqual(spawnCall.config.additionalWorkspaceRoots, descriptor.grantedRoots)
        XCTAssertTrue(spawnCall.config.allowedDirectories.isEmpty)
        XCTAssertTrue(createCalls.isEmpty)
        XCTAssertEqual(
            providerSetupCalls,
            [.init(providerId: "codex", workingDirectory: descriptor.primaryRoot, autoTrust: true)]
        )
    }

    func testProjectlessTaskHiddenSetupUsesItsWorkspace() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true,
            hasCompletedInitialSetup: false,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        try await fixture.viewModel.setupHiddenInitialRuntimeIfNeeded()

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let spawnCall = try XCTUnwrap(spawnCalls.first)
        XCTAssertFalse(try fixture.dbThread().isDraft)
        XCTAssertTrue(try fixture.dbThread().hasCompletedInitialSetup)
        XCTAssertEqual(spawnCall.config.workingDirectory, descriptor.primaryRoot)
        XCTAssertEqual(spawnCall.config.additionalWorkspaceRoots, descriptor.grantedRoots)
    }

    func testTaskFirstMessageMaterializationPersistsModifiedAt() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true,
            hasCompletedInitialSetup: false,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        try await fixture.viewModel.setupAndStart("Run the task")

        XCTAssertFalse(try fixture.dbThread().isDraft)
        XCTAssertNotNil(try fixture.dbThread().modifiedAt)
    }

    func testTaskExternalWorkspaceIsNotAutomaticallyTrusted() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let externalRoot = try environment.createDirectory(named: "external")
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: externalRoot.path,
            ownershipStrategy: .projectLocal
        )
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        try await fixture.viewModel.setupHiddenInitialRuntimeIfNeeded()

        let providerSetupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(
            providerSetupCalls,
            [.init(providerId: "claude", workingDirectory: descriptor.primaryRoot, autoTrust: false)]
        )
    }

    func testTaskOwnedWorktreeIsNotAutomaticallyTrusted() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let worktreeRoot = try environment.createDirectory(named: "worktree")
        let sourceProjectRoot = try environment.createDirectory(named: "source-project")
        let descriptor = try environment.service.registerOwnedWorktree(
            at: worktreeRoot.path,
            sourceProjectPath: sourceProjectRoot.path,
            grantedRoots: []
        )
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        try await fixture.viewModel.setupHiddenInitialRuntimeIfNeeded()

        let providerSetupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(
            providerSetupCalls,
            [.init(providerId: "claude", workingDirectory: descriptor.primaryRoot, autoTrust: false)]
        )
    }

    func testFailedTaskSetupRetainsOwnedWorkspaceAndDescriptor() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )
        await fixture.agentsManager.enqueueSpawnError(MockAgentsManager.MockError.sendFailed)

        do {
            try await fixture.viewModel.setupAndStart("Run the task")
            XCTFail("Expected task setup to fail")
        } catch MockAgentsManager.MockError.sendFailed {
            // expected
        }

        XCTAssertEqual(try fixture.dbThread().taskWorkspaceDescriptor, descriptor)
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: descriptor.primaryRoot))
    }

    func testIdleTaskGrantChangePersistsAndReconfiguresTrackedRuntime() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let addedGrant = try environment.createDirectory(named: "grant-c")
        let fixture = try ConversationViewModelTestFixture(
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        fixture.viewModel.addTaskWorkspaceGrants([addedGrant])
        try await waitUntil("task runtime reconfigured with added grant") {
            await fixture.agentsManager.reconfigureCalls().count == 1
        }

        let expectedGrants = descriptor.grantedRoots + [addedGrant.path]
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(try fixture.dbThread().taskWorkspaceDescriptor?.grantedRoots, expectedGrants)
        XCTAssertEqual(reconfigureCalls.first?.config.additionalWorkspaceRoots, expectedGrants)
    }

    func testIdleTaskGrantRemovalPersistsAndReconfiguresTrackedRuntime() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let removedGrant = try XCTUnwrap(descriptor.grantedRoots.first)
        let fixture = try ConversationViewModelTestFixture(
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        fixture.viewModel.removeTaskWorkspaceGrant(removedGrant)
        try await waitUntil("task runtime reconfigured with removed grant") {
            fixture.viewModel.isUpdatingTaskWorkspaceConfiguration == false
        }

        let expectedGrants = Array(descriptor.grantedRoots.dropFirst())
        XCTAssertEqual(try fixture.dbThread().taskWorkspaceDescriptor?.grantedRoots, expectedGrants)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.first?.config.additionalWorkspaceRoots, expectedGrants)
    }

    func testMissingTaskGrantsCanBeRemovedIndependently() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        for grant in descriptor.grantedRoots {
            try FileManager.default.removeItem(atPath: grant)
        }
        let fixture = try ConversationViewModelTestFixture(
            initialAgentIsRunning: false,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        fixture.viewModel.removeTaskWorkspaceGrant(descriptor.grantedRoots[0])
        try await waitUntil("first stale task grant removed") {
            fixture.viewModel.isUpdatingTaskWorkspaceConfiguration == false
        }
        XCTAssertEqual(
            try fixture.dbThread().taskWorkspaceDescriptor?.grantedRoots,
            [descriptor.grantedRoots[1]]
        )

        fixture.viewModel.removeTaskWorkspaceGrant(descriptor.grantedRoots[1])
        try await waitUntil("second stale task grant removed") {
            fixture.viewModel.isUpdatingTaskWorkspaceConfiguration == false
        }
        XCTAssertEqual(try fixture.dbThread().taskWorkspaceDescriptor?.grantedRoots, [])
    }

    func testAddingTaskGrantPreservesExistingMissingGrant() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let missingGrant = descriptor.grantedRoots[0]
        try FileManager.default.removeItem(atPath: missingGrant)
        let addedGrant = try environment.createDirectory(named: "grant-c")
        let fixture = try ConversationViewModelTestFixture(
            initialAgentIsRunning: false,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        fixture.viewModel.addTaskWorkspaceGrants([addedGrant])
        try await waitUntil("task grant added alongside stale grant") {
            fixture.viewModel.isUpdatingTaskWorkspaceConfiguration == false
        }

        XCTAssertEqual(
            try fixture.dbThread().taskWorkspaceDescriptor?.grantedRoots,
            descriptor.grantedRoots + [addedGrant.path]
        )
    }

    func testBusyTaskRejectsGrantChange() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let addedGrant = try environment.createDirectory(named: "grant-c")
        let fixture = try ConversationViewModelTestFixture(
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)

        XCTAssertFalse(fixture.viewModel.canEditTaskWorkspaceConfiguration)
        fixture.viewModel.addTaskWorkspaceGrants([addedGrant])
        try await waitUntil("busy task grant change rejected") {
            fixture.viewModel.state.lastTurnError != nil
        }

        XCTAssertEqual(try fixture.dbThread().taskWorkspaceDescriptor, descriptor)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testSuspendedTaskGrantChangePersistsWithoutWakingRuntime() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let addedGrant = try environment.createDirectory(named: "grant-c")
        let fixture = try ConversationViewModelTestFixture(
            initialAgentIsRunning: false,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        fixture.viewModel.addTaskWorkspaceGrants([addedGrant])
        try await waitUntil("suspended task grant persisted") {
            fixture.viewModel.isUpdatingTaskWorkspaceConfiguration == false
        }

        XCTAssertEqual(
            try fixture.dbThread().taskWorkspaceDescriptor?.grantedRoots,
            descriptor.grantedRoots + [addedGrant.path]
        )
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testDeferredTaskGrantReplacementRollsBackPersistedAndRuntimeRoots() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let addedGrant = try environment.createDirectory(named: "grant-c")
        let fixture = try ConversationViewModelTestFixture(
            reconfigureResult: .nextTurnRequired,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        fixture.viewModel.addTaskWorkspaceGrants([addedGrant])
        try await waitUntil("deferred task grant rolled back") {
            fixture.viewModel.isUpdatingTaskWorkspaceConfiguration == false
        }

        XCTAssertEqual(try fixture.dbThread().taskWorkspaceDescriptor, descriptor)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 2)
        XCTAssertEqual(reconfigureCalls[0].config.additionalWorkspaceRoots, descriptor.grantedRoots + [addedGrant.path])
        XCTAssertEqual(reconfigureCalls[1].config.additionalWorkspaceRoots, descriptor.grantedRoots)
    }

    func testFailedTaskGrantReplacementSurfacesRollbackFailure() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let addedGrant = try environment.createDirectory(named: "grant-c")
        let fixture = try ConversationViewModelTestFixture(
            reconfigureError: .reconfigureFailed,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        fixture.viewModel.addTaskWorkspaceGrants([addedGrant])
        try await waitUntil("failed task grant replacement rolled back") {
            fixture.viewModel.isUpdatingTaskWorkspaceConfiguration == false
        }

        XCTAssertEqual(try fixture.dbThread().taskWorkspaceDescriptor, descriptor)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 2)
        let error = try XCTUnwrap(fixture.viewModel.state.lastTurnError)
        XCTAssertTrue(error.contains("Folder access could not be applied"))
        XCTAssertTrue(error.contains("rollback was incomplete"))
        XCTAssertTrue(error.contains("restoring the current session failed"))
    }

    func testTaskGrantChangesSerializeAndBlockOutboundReservation() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let addedGrant = try environment.createDirectory(named: "grant-c")
        let rejectedRemoval = try XCTUnwrap(descriptor.grantedRoots.first)
        let fixture = try ConversationViewModelTestFixture(
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )

        fixture.viewModel.addTaskWorkspaceGrants([addedGrant])
        XCTAssertFalse(fixture.viewModel.canEditTaskWorkspaceConfiguration)
        XCTAssertThrowsError(try fixture.viewModel.ensureCanReserveOutbound()) { error in
            XCTAssertEqual(error.localizedDescription, "Task folder access is still being applied")
        }
        fixture.viewModel.removeTaskWorkspaceGrant(rejectedRemoval)

        try await waitUntil("serialized task grant update completed") {
            fixture.viewModel.isUpdatingTaskWorkspaceConfiguration == false
        }

        let expectedGrants = descriptor.grantedRoots + [addedGrant.path]
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(try fixture.dbThread().taskWorkspaceDescriptor?.grantedRoots, expectedGrants)
        XCTAssertEqual(reconfigureCalls.count, 1)
    }

    func testTaskWithMultipleConversationsDisablesGrantChanges() throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let descriptor = try environment.privateDescriptorWithGrants()
        let addedGrant = try environment.createDirectory(named: "grant-c")
        let fixture = try ConversationViewModelTestFixture(
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            taskWorkspaceOwnershipService: environment.service
        )
        let secondary = Conversation(id: "task-secondary", isMain: false, thread: fixture.thread)
        fixture.thread.conversations.append(secondary)
        fixture.context.insert(secondary)
        try fixture.context.save()

        XCTAssertFalse(fixture.viewModel.canEditTaskWorkspaceConfiguration)
        XCTAssertEqual(
            fixture.viewModel.taskWorkspaceConfigurationDisabledReason,
            "Folder access can only be changed while the task has one conversation."
        )
        fixture.viewModel.addTaskWorkspaceGrants([addedGrant])

        XCTAssertEqual(try fixture.dbThread().taskWorkspaceDescriptor, descriptor)
        XCTAssertEqual(
            fixture.viewModel.state.lastTurnError,
            "Folder access can only be changed while the task has one conversation."
        )
    }

    func testTaskDraftMaterializationRecordsTaskActivity() throws {
        let recorder = RecordingThreadActivityRecorder()
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/task-materialization",
            ownershipStrategy: .privateOwned
        )
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true,
            threadMode: .task,
            taskWorkspaceDescriptor: descriptor,
            threadActivityRecorder: recorder
        )

        try fixture.viewModel.materializeDraftWithoutMessageIfNeeded()

        XCTAssertEqual(recorder.materializedTaskConversationIDs, [fixture.conversation.id])
        XCTAssertNotNil(try fixture.dbThread().modifiedAt)
    }

    func testProjectDraftMaterializationDoesNotRecordTaskActivity() throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true,
            threadActivityRecorder: recorder
        )

        try fixture.viewModel.materializeDraftWithoutMessageIfNeeded()

        XCTAssertTrue(recorder.materializedTaskConversationIDs.isEmpty)
    }
}

private final class TaskWorkspaceTestEnvironment {
    let root: URL
    let service: DefaultTaskWorkspaceOwnershipService

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-task-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        self.service = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: root.appendingPathComponent("private", isDirectory: true),
            worktreeOwnershipRecordsRoot: root.appendingPathComponent("worktrees", isDirectory: true)
        )
    }

    func privateDescriptorWithGrants() throws -> TaskWorkspaceDescriptor {
        let ownedDescriptor = try service.createPrivateWorkspace()
        let grantA = try createDirectory(named: "grant-a")
        let grantB = try createDirectory(named: "grant-b")
        return TaskWorkspaceDescriptor(
            primaryRoot: ownedDescriptor.primaryRoot,
            grantedRoots: [grantA.path, grantB.path, grantA.path],
            ownershipStrategy: ownedDescriptor.ownershipStrategy,
            ownershipMarkerID: ownedDescriptor.ownershipMarkerID
        )
    }

    func createDirectory(named name: String) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
