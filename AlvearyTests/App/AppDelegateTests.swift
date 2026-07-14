import AppKit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class AppDelegateTests: XCTestCase {
    func testLaunchRemovesStaleDraftRowsAndAttachmentDirectory() async throws {
        let fixture = try AppDelegateTestFixture()
        let context = ModelContext(fixture.modelContainer)
        let project = Project(path: "/tmp/stale-draft", name: "Stale")
        let thread = AgentThread(name: "New thread", isDraft: true, project: project)
        let conversation = Conversation(id: "stale-draft-main", provider: "claude", thread: thread)
        context.insert(project)
        context.insert(thread)
        context.insert(conversation)
        try context.save()
        let mainContext = fixture.modelContainer.mainContext
        let preloadedDrafts = try mainContext.fetch(FetchDescriptor<AgentThread>())
        XCTAssertEqual(preloadedDrafts.map(\.persistentModelID), [thread.persistentModelID])
        let attachment = try await fixture.attachmentStore.storeAppShotScreenshot(
            Data("png".utf8),
            conversationId: conversation.id,
            label: "Appshot screenshot.png"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.fileURL.path))

        let appDelegate = fixture.makeAppDelegate()
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await fixture.waitForProviderChecks(1, description: "expected startup cleanup to finish")

        XCTAssertEqual(try mainContext.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.fileURL.path))
        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        withExtendedLifetime(preloadedDrafts) {}
    }

    func testStaleDraftCleanupSaveFailureRollsBackPendingDeletion() throws {
        let fixture = try AppDelegateTestFixture()
        let context = fixture.modelContainer.mainContext
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let thread = AgentThread(
            name: "New task",
            isDraft: true,
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        let conversation = Conversation(id: "stale-draft-save-failure-main", provider: "claude", thread: thread)
        context.insert(thread)
        context.insert(conversation)
        try context.save()
        let threadID = thread.persistentModelID
        let appDelegate = fixture.makeAppDelegate()

        let removedConversationIDs = appDelegate.removeStaleDraftThreads { _ in
            throw AppDelegateDraftCleanupTestError.saveFailed
        }

        XCTAssertTrue(removedConversationIDs.isEmpty)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<AgentThread>()).map(\.persistentModelID),
            [threadID]
        )
        XCTAssertEqual(try ModelContext(fixture.modelContainer).fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.primaryRoot))
    }

    func testStaleTaskDraftCleanupRemovesOnlyItsOwnedWorkspace() throws {
        let fixture = try AppDelegateTestFixture()
        let context = fixture.modelContainer.mainContext
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let grantedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-stale-task-grant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: grantedRoot, withIntermediateDirectories: true)
        let taskWorkspace = TaskWorkspaceDescriptor(
            primaryRoot: workspace.primaryRoot,
            grantedRoots: [grantedRoot.path],
            ownershipStrategy: workspace.ownershipStrategy,
            ownershipMarkerID: workspace.ownershipMarkerID
        )
        let thread = AgentThread(
            name: "New task",
            isDraft: true,
            mode: .task,
            taskWorkspaceDescriptor: taskWorkspace
        )
        let conversation = Conversation(id: "stale-task-main", provider: "codex", thread: thread)
        context.insert(thread)
        context.insert(conversation)
        try context.save()
        let conversationID = conversation.id

        let removedConversationIDs = fixture.makeAppDelegate().removeStaleDraftThreads()

        XCTAssertEqual(removedConversationIDs, [conversationID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.primaryRoot))
        XCTAssertTrue(FileManager.default.fileExists(atPath: grantedRoot.path))
        try? FileManager.default.removeItem(at: grantedRoot)
    }

    func testStaleDraftCleanupRetriesPreviouslyOrphanedPrivateWorkspace() throws {
        let fixture = try AppDelegateTestFixture()
        let orphanedWorkspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()

        let removedConversationIDs = fixture.makeAppDelegate().removeStaleDraftThreads()

        XCTAssertTrue(removedConversationIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanedWorkspace.primaryRoot))
    }

    func testStaleDraftCleanupRetainsPreparedPrivateWorkspaceBeforeRunRecovery() throws {
        let fixture = try AppDelegateTestFixture()
        let context = fixture.modelContainer.mainContext
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let run = ScheduledTaskRun(
            occurrenceID: UUID().uuidString,
            definitionID: "prepared-private-workspace",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
            triggerKind: .scheduled,
            status: .preparing,
            titleSnapshot: "Prepared private workspace",
            promptSnapshot: "Run scheduled work.",
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree
        )
        run.preparedWorkspaceRoot = workspace.primaryRoot
        run.preparedWorkspaceOwnershipStrategy = .privateOwned
        run.preparedWorkspaceMarkerID = workspace.ownershipMarkerID
        context.insert(run)
        try context.save()

        _ = fixture.makeAppDelegate().removeStaleDraftThreads()

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.primaryRoot))
        XCTAssertNil(run.thread)
    }

    func testStaleDraftCleanupRetainsPreparedPrivateWorkspaceWithUnknownRunStatus() throws {
        let fixture = try AppDelegateTestFixture()
        let context = fixture.modelContainer.mainContext
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let run = ScheduledTaskRun(
            occurrenceID: UUID().uuidString,
            definitionID: "unknown-status-private-workspace",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
            triggerKind: .scheduled,
            status: .failure,
            titleSnapshot: "Unknown status private workspace",
            promptSnapshot: "Run scheduled work.",
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree
        )
        run.statusRawValue = "future-status"
        run.preparedWorkspaceRoot = workspace.primaryRoot
        run.preparedWorkspaceOwnershipStrategy = .privateOwned
        run.preparedWorkspaceMarkerID = workspace.ownershipMarkerID
        context.insert(run)
        try context.save()

        _ = fixture.makeAppDelegate().removeStaleDraftThreads()

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.primaryRoot))
        XCTAssertNil(run.thread)
    }

    func testStaleCleanupRetainsTerminalPreparedPrivateWorkspaceUntilTaskDeletion() throws {
        let fixture = try AppDelegateTestFixture()
        let context = fixture.modelContainer.mainContext
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let run = ScheduledTaskRun(
            occurrenceID: UUID().uuidString,
            definitionID: "terminal-private-workspace",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
            triggerKind: .scheduled,
            status: .interrupted,
            titleSnapshot: "Terminal private workspace",
            promptSnapshot: "Run scheduled work.",
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree
        )
        run.preparedWorkspaceRoot = workspace.primaryRoot
        run.preparedWorkspaceOwnershipStrategy = .privateOwned
        run.preparedWorkspaceMarkerID = workspace.ownershipMarkerID
        let thread = AgentThread(name: "Interrupted scheduled task", mode: .task, scheduledTaskRun: run)
        run.thread = thread
        context.insert(run)
        context.insert(thread)
        try context.save()

        _ = fixture.makeAppDelegate().removeStaleDraftThreads()

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.primaryRoot))

        context.delete(thread)
        try context.save()
        _ = fixture.makeAppDelegate().removeStaleDraftThreads()

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.primaryRoot))
    }

    func testStaleCleanupRetainsPrivateWorkspaceForEffectiveTaskWithUnknownRawMode() throws {
        let fixture = try AppDelegateTestFixture()
        let context = fixture.modelContainer.mainContext
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let orphanedWorkspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let run = ScheduledTaskRun(
            occurrenceID: UUID().uuidString,
            definitionID: "unknown-thread-mode-private-workspace",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
            triggerKind: .scheduled,
            status: .success,
            titleSnapshot: "Unknown thread mode private workspace",
            promptSnapshot: "Run scheduled work.",
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree
        )
        let thread = AgentThread(
            name: "Completed scheduled task",
            mode: .task,
            taskWorkspaceDescriptor: workspace,
            scheduledTaskRun: run
        )
        run.thread = thread
        context.insert(run)
        context.insert(thread)
        try context.save()
        thread.modeRawValue = "future-mode"
        try context.save()

        XCTAssertEqual(thread.effectiveMode, .task)
        XCTAssertNil(thread.taskWorkspaceDescriptor)

        _ = fixture.makeAppDelegate().removeStaleDraftThreads()

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.primaryRoot))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanedWorkspace.primaryRoot))
    }

    func testStaleDraftCleanupDoesNotRetainMismatchedPreparedWorkspaceOwnership() throws {
        let fixture = try AppDelegateTestFixture()
        let context = fixture.modelContainer.mainContext
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let run = ScheduledTaskRun(
            occurrenceID: UUID().uuidString,
            definitionID: "mismatched-private-workspace",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
            triggerKind: .scheduled,
            status: .preparing,
            titleSnapshot: "Mismatched private workspace",
            promptSnapshot: "Run scheduled work.",
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree
        )
        run.preparedWorkspaceRoot = workspace.primaryRoot
        run.preparedWorkspaceOwnershipStrategy = .projectLocal
        run.preparedWorkspaceMarkerID = workspace.ownershipMarkerID
        context.insert(run)
        try context.save()

        _ = fixture.makeAppDelegate().removeStaleDraftThreads()

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.primaryRoot))
    }

    func testStartupWarmupLoadsSessionsTerminatesOnlySessionMappedOrphansAndChecksProviders() async throws {
        let fixture = try AppDelegateTestFixture()
        try fixture.insertConversations(["conversation-1", "conversation-2"])
        await fixture.seedSessions([
            (conversationId: "conversation-1", cwd: "/tmp/project-one"),
            (conversationId: "conversation-2", cwd: "/tmp/project-two")
        ])
        await fixture.agentsManager.setTrackedConversationIds(["conversation-2"])

        await fixture.shellRunner.enqueue(fixture.shellSuccess(
            stdout: AppDelegateClaudeProcessListBuilder()
                .claude(pid: 100, sessionId: "session-1")
                .claude(pid: 200, sessionId: "session-2")
                .other(pid: 300, command: "/bin/bash -lc echo nope")
                .build()
        ))
        await fixture.shellRunner.enqueue(fixture.shellSuccess(stdout: "p100\nfcwd\nn/tmp/project-one\n"))
        await fixture.shellRunner.enqueue(fixture.shellSuccess(stdout: "p200\nfcwd\nn/tmp/project-two\n"))

        let signalState = AppDelegateProcessSignalState(activePIDs: [100, 200])
        let appDelegate = fixture.makeAppDelegate(signalState: signalState)

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await fixture.waitForProviderChecks(1, description: "expected startup warmup to finish")

        let sessionLoadCount = await fixture.sessionManager.loadCount()
        let providerCheckCount = await fixture.providerDetection.checkAllCount()
        let preservedSession = await fixture.sessionManager.hasSession(for: "conversation-1")
        XCTAssertEqual(sessionLoadCount, 1)
        XCTAssertEqual(providerCheckCount, 1)
        XCTAssertTrue(preservedSession)
        XCTAssertEqual(signalState.recordedSignals(), [.init(pid: 100, signal: SIGTERM)])
        XCTAssertTrue(signalState.contains(200))

        let invocations = await fixture.shellRunner.invocations
        XCTAssertEqual(invocations.map(\.executable), ["/bin/ps", "/usr/sbin/lsof", "/usr/sbin/lsof"])

        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testWakeNotificationCancelsOlderRefreshBeforeRunningProviderCheck() async throws {
        let fixture = try AppDelegateTestFixture()
        let appDelegate = fixture.makeAppDelegate(wakeRefreshDelay: .milliseconds(40))

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await fixture.waitForProviderChecks(1, description: "expected initial startup provider detection")

        fixture.workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(10))
        fixture.workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        try await fixture.waitForProviderChecks(2, description: "expected only latest wake refresh to run")
        try? await Task.sleep(for: .milliseconds(60))

        let providerCheckCount = await fixture.providerDetection.checkAllCount()
        XCTAssertEqual(providerCheckCount, 2)
        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testStartupWarmupRemovesSessionEntryWhenOrphanedConversationWasDeleted() async throws {
        let fixture = try AppDelegateTestFixture()

        await fixture.seedSessions([(conversationId: "conversation-1", cwd: "/tmp/project-one")])
        await fixture.shellRunner.enqueue(fixture.shellSuccess(
            stdout: AppDelegateClaudeProcessListBuilder()
                .claude(pid: 100, sessionId: "session-1")
                .build()
        ))
        await fixture.shellRunner.enqueue(fixture.shellSuccess(stdout: "p100\nfcwd\nn/tmp/project-one\n"))

        let signalState = AppDelegateProcessSignalState(activePIDs: [100])
        let appDelegate = fixture.makeAppDelegate(signalState: signalState)

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await appDelegateWaitUntil("expected startup warmup to prune stale session entry") {
            !(await fixture.sessionManager.hasSession(for: "conversation-1"))
        }

        let providerCheckCount = await fixture.providerDetection.checkAllCount()
        XCTAssertEqual(providerCheckCount, 1)
        XCTAssertEqual(signalState.recordedSignals(), [.init(pid: 100, signal: SIGTERM)])

        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testManagedProcessesObserverTogglesSuddenTerminationWithSnapshotChanges() async throws {
        let fixture = try AppDelegateTestFixture()
        let suddenTerminationState = AppDelegateSuddenTerminationState()
        let appDelegate = fixture.makeAppDelegate(
            disableSuddenTermination: {
                suddenTerminationState.recordDisable()
            },
            enableSuddenTermination: {
                suddenTerminationState.recordEnable()
            }
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        await fixture.agentsManager.setAllProcessesSnapshot([Process()])
        fixture.appNotificationCenter.post(name: .managedProcessesChanged, object: nil)
        XCTAssertEqual(suddenTerminationState.disableCalls, 1)
        XCTAssertEqual(suddenTerminationState.enableCalls, 0)

        await fixture.agentsManager.setAllProcessesSnapshot([])
        fixture.appNotificationCenter.post(name: .managedProcessesChanged, object: nil)
        XCTAssertEqual(suddenTerminationState.disableCalls, 1)
        XCTAssertEqual(suddenTerminationState.enableCalls, 1)

        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testApplicationWillTerminateBeginsShutdownPostsNotificationAndPersistsSessionMap() async throws {
        let fixture = try AppDelegateTestFixture()
        let flushRecorder = AppDelegateNotificationCounter()
        let shutdownOrderRecorder = AppDelegateShutdownOrderRecorder()
        fixture.agentsManager.setShutdownOrderRecorder(shutdownOrderRecorder)
        let appDelegate = fixture.makeAppDelegate(
            shutdownPersistTimeout: 0.2,
            flushConversationControllers: {
                flushRecorder.increment()
                shutdownOrderRecorder.record("flush")
                return []
            }
        )

        let appWillTerminateNotifications = AppDelegateNotificationCounter()
        let observer = fixture.appNotificationCenter.addObserver(
            forName: .appWillTerminate,
            object: nil,
            queue: nil
        ) { _ in
            appWillTerminateNotifications.increment()
        }
        defer {
            fixture.appNotificationCenter.removeObserver(observer)
        }

        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        let shutdownCallCount = await fixture.agentsManager.beginShutdownCallCount()
        let persistCount = await fixture.sessionManager.persistCount()
        XCTAssertEqual(shutdownCallCount, 1)
        XCTAssertEqual(persistCount, 1)
        XCTAssertEqual(flushRecorder.value, 1)
        XCTAssertEqual(shutdownOrderRecorder.values, ["flush", "shutdown"])
        XCTAssertEqual(appWillTerminateNotifications.value, 1)
    }

    func testApplicationWillTerminateStillShutsDownAfterControllerFlushFailure() async throws {
        let fixture = try AppDelegateTestFixture()
        let appDelegate = fixture.makeAppDelegate(
            flushConversationControllers: {
                [ConversationControllerFlushFailure(
                    key: ConversationControllerKey(conversationID: "conversation-1"),
                    message: "save failed"
                )]
            }
        )

        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        let shutdownCallCount = await fixture.agentsManager.beginShutdownCallCount()
        XCTAssertEqual(shutdownCallCount, 1)
    }
}

extension AppDelegateTests {
    func testLaunchCleanupRemovesPreexistingDraftAndPreservesDraftCreatedAfterDelegateInitialization() async throws {
        let fixture = try AppDelegateTestFixture()
        let context = fixture.modelContainer.mainContext
        let staleThread = AgentThread(name: "New thread", isDraft: true)
        let staleConversation = Conversation(id: "preexisting-launch-draft-main", provider: "codex", thread: staleThread)
        context.insert(staleThread)
        context.insert(staleConversation)
        try context.save()
        let appDelegate = fixture.makeAppDelegate()

        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        let thread = AgentThread(
            name: "New task",
            isDraft: true,
            mode: .task,
            taskWorkspaceDescriptor: workspace
        )
        let conversation = Conversation(id: "current-launch-task-main", provider: "claude", thread: thread)
        context.insert(thread)
        context.insert(conversation)
        try context.save()

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await fixture.waitForProviderChecks(1, description: "expected startup cleanup to finish")

        XCTAssertEqual(try context.fetch(FetchDescriptor<AgentThread>()).map(\.persistentModelID), [thread.persistentModelID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Conversation>()).map(\.persistentModelID), [conversation.persistentModelID])
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.primaryRoot))
        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
}

private enum AppDelegateDraftCleanupTestError: Error {
    case saveFailed
}
