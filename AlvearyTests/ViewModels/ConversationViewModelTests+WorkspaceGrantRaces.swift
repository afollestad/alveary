import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testReusedScheduleDisablesGrantEditingWithoutChangingSavedRoots() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let primary = try environment.createDirectory(named: "primary")
        let addition = try environment.createDirectory(named: "added-grant")
        let fixture = try ConversationViewModelTestFixture(projectPath: primary.path)
        let originalGrant = SourceFolderSnapshot(path: "/tmp/saved-schedule-grant")
        try fixture.thread.replaceAdditionalFolders([originalGrant])
        let schedule = try attachGrantRaceReuseSchedule(fixture)
        let workspace = fixture.thread.workspaceSnapshot
        let reason = SidebarViewModelError.scheduledTaskAttachment(schedule.title).localizedDescription

        XCTAssertFalse(fixture.viewModel.canEditTaskWorkspaceConfiguration)
        XCTAssertEqual(fixture.viewModel.taskWorkspaceConfigurationDisabledReason, reason)
        XCTAssertNil(fixture.thread.blockingScheduledTaskAttachment)
        fixture.viewModel.addTaskWorkspaceGrants([addition])
        fixture.viewModel.removeTaskWorkspaceGrant(originalGrant.path)
        try await waitUntil("attached schedule grant edits finish") { !fixture.viewModel.isUpdatingTaskWorkspaceConfiguration }

        XCTAssertEqual(fixture.thread.workspaceSnapshot, workspace)
        XCTAssertEqual(schedule.workspaceSnapshot, workspace)
        XCTAssertEqual(schedule.grantedRoots, [originalGrant.path])
        XCTAssertEqual(fixture.viewModel.state.lastTurnError, reason)
        let reconfigurations = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigurations.isEmpty)
        schedule.reusedThread = nil
        try fixture.context.save()
        XCTAssertTrue(fixture.viewModel.canEditTaskWorkspaceConfiguration)
    }

    func testReuseAttachmentDuringQueuedOrResolvingGrantEditPreservesRoots() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let primary = try environment.createDirectory(named: "primary")
        let addition = try environment.createDirectory(named: "added-grant")
        for duringDiscovery in [false, true] {
            let gate = WorkspaceGrantResolutionGate()
            defer { Task { await gate.release() } }
            let fixture = try ConversationViewModelTestFixture(projectPath: primary.path, resolveSourceFolder: { await gate.resolve($0) })
            let workspace = fixture.thread.workspaceSnapshot
            fixture.viewModel.addTaskWorkspaceGrants([addition])
            if duringDiscovery {
                try await waitUntil("grant discovery begins before schedule attaches") { await gate.hasEntered }
            }
            let schedule = try attachGrantRaceReuseSchedule(fixture)
            await gate.release()
            try await waitUntil("grant edit rejects newly attached reuse schedule") { !fixture.viewModel.isUpdatingTaskWorkspaceConfiguration }

            XCTAssertFalse(fixture.viewModel.canEditTaskWorkspaceConfiguration)
            XCTAssertEqual(fixture.thread.workspaceSnapshot, workspace)
            XCTAssertEqual(schedule.workspaceSnapshot, workspace)
            XCTAssertEqual(schedule.grantedRoots, workspace?.grants.map(\.path))
            let reconfigurations = await fixture.agentsManager.reconfigureCalls()
            XCTAssertTrue(reconfigurations.isEmpty)
        }
    }

    func testQueuedGrantEditsDoNotFollowDraftToAnotherWorkspace() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let primary = try environment.createDirectory(named: "primary")
        let grant = try environment.createDirectory(named: "shared-grant")
        let addition = try environment.createDirectory(named: "added-grant")
        for removesGrant in [false, true] {
            let fixture = try ConversationViewModelTestFixture(isDraft: true, hasCompletedInitialSetup: false, projectPath: primary.path)
            try fixture.thread.replaceAdditionalFolders([SourceFolderSnapshot(path: grant.path)])
            let destination = Project(name: "Other project", folders: [
                SourceFolderSnapshot(path: "/tmp/other-draft-source"), SourceFolderSnapshot(path: grant.path)
            ])
            fixture.context.insert(destination)
            try fixture.context.save()
            if removesGrant {
                fixture.viewModel.removeTaskWorkspaceGrant(grant.path)
            } else {
                fixture.viewModel.addTaskWorkspaceGrants([addition])
            }
            _ = try grantRaceDraftEditor(fixture).moveDraftThread(fixture.thread, to: .project(id: destination.id))
            let destinationWorkspace = fixture.thread.workspaceSnapshot
            fixture.viewModel.state.lastTurnError = "Current destination message"

            try await waitUntil("queued grant edit rejected after draft move") { !fixture.viewModel.isUpdatingTaskWorkspaceConfiguration }

            XCTAssertEqual(fixture.thread.project?.id, destination.id)
            XCTAssertEqual(fixture.thread.workspaceSnapshot, destinationWorkspace)
            XCTAssertFalse(fixture.thread.draftHasExplicitGrants)
            XCTAssertEqual(fixture.viewModel.state.lastTurnError, "Current destination message")
            let reconfigurations = await fixture.agentsManager.reconfigureCalls()
            XCTAssertTrue(reconfigurations.isEmpty)
        }
    }

    func testGrantDiscoveryDoesNotFollowDraftBetweenProjectsSharingFolders() async throws {
        let environment = try TaskWorkspaceTestEnvironment()
        defer { environment.remove() }
        let primary = try environment.createDirectory(named: "primary")
        let addition = try environment.createDirectory(named: "added-grant")
        let gate = WorkspaceGrantResolutionGate()
        defer { Task { await gate.release() } }
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true, hasCompletedInitialSetup: false, projectPath: primary.path,
            resolveSourceFolder: { path in
                await gate.resolve(path)
            }
        )
        let originalWorkspace = try XCTUnwrap(fixture.thread.workspaceSnapshot)
        let destination = Project(name: "Same folders, other project", folders: originalWorkspace.sourceFolders)
        fixture.context.insert(destination)
        try fixture.context.save()
        fixture.viewModel.addTaskWorkspaceGrants([addition])
        try await waitUntil("folder metadata resolution in flight") {
            await gate.hasEntered || !fixture.viewModel.isUpdatingTaskWorkspaceConfiguration
        }
        guard await gate.hasEntered else {
            XCTFail(fixture.viewModel.state.lastTurnError ?? "Grant edit ended before resolving folder metadata")
            return
        }

        _ = try grantRaceDraftEditor(fixture).moveDraftThread(fixture.thread, to: .project(id: destination.id))
        XCTAssertEqual(fixture.thread.workspaceSnapshot, originalWorkspace)
        fixture.viewModel.state.lastTurnError = "Current destination message"
        await gate.release()
        try await waitUntil("resolved grant edit rejected after placement move") { !fixture.viewModel.isUpdatingTaskWorkspaceConfiguration }

        XCTAssertEqual(fixture.thread.project?.id, destination.id)
        XCTAssertEqual(fixture.thread.workspaceSnapshot, originalWorkspace)
        XCTAssertFalse(fixture.thread.draftHasExplicitGrants)
        XCTAssertEqual(fixture.viewModel.state.lastTurnError, "Current destination message")
        let reconfigurations = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigurations.isEmpty)
    }
}

@MainActor
private func attachGrantRaceReuseSchedule(_ fixture: ConversationViewModelTestFixture) throws -> ScheduledTask {
    let schedule = ScheduledTask(
        title: "Rolling schedule", prompt: "Check the project", destination: .reusedThread,
        recurrence: .daily(hour: 9, minute: 0), timeZoneIdentifier: "UTC", providerID: "claude",
        workspaceKind: .project, workspaceStrategy: .localCheckout, project: fixture.project,
        workspaceSnapshot: fixture.thread.workspaceSnapshot
    )
    schedule.reusedThread = fixture.thread
    fixture.context.insert(schedule)
    try fixture.context.save()
    return schedule
}

@MainActor
private func grantRaceDraftEditor(_ fixture: ConversationViewModelTestFixture) -> SidebarViewModel {
    SidebarViewModel(
        agentsManager: fixture.agentsManager, modelContext: fixture.context, shell: MockShellRunner(),
        gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
        worktreeManager: fixture.worktreeManager, settingsService: fixture.settingsService,
        taskWorkspaceOwnershipService: fixture.taskWorkspaceOwnershipService, notificationManager: RecordingNotificationManager()
    )
}

private actor WorkspaceGrantResolutionGate {
    private(set) var hasEntered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func resolve(_ path: String) async -> SourceFolderSnapshot {
        hasEntered = true
        await withCheckedContinuation { continuation = $0 }
        return SourceFolderSnapshot(path: path)
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
