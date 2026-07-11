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
        let project = Project(path: "/tmp/stale-draft-save-failure", name: "Stale")
        let thread = AgentThread(name: "New thread", isDraft: true, project: project)
        let conversation = Conversation(id: "stale-draft-save-failure-main", provider: "claude", thread: thread)
        context.insert(project)
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
        let appDelegate = fixture.makeAppDelegate(shutdownPersistTimeout: 0.2)

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
        XCTAssertEqual(appWillTerminateNotifications.value, 1)
    }
}

private enum AppDelegateDraftCleanupTestError: Error {
    case saveFailed
}
