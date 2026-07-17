import AppKit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension AppDelegateTests {
    func testWakeNotificationCancelsOlderRefreshBeforeRunningProviderCheck() async throws {
        let fixture = try AppDelegateTestFixture()
        let lifecycle = AppDelegateScheduledTaskLifecycleSpy()
        let appDelegate = fixture.makeAppDelegate(
            wakeRefreshDelay: .milliseconds(40),
            scheduledTaskLifecycle: lifecycle
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await fixture.waitForProviderChecks(1, description: "expected initial startup provider detection")
        try await appDelegateWaitUntil("expected scheduled task activation after provider refresh") {
            lifecycle.activationCount == 1
        }

        fixture.workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(10))
        fixture.workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        try await fixture.waitForProviderChecks(2, description: "expected only latest wake refresh to run")
        try? await Task.sleep(for: .milliseconds(60))

        let providerCheckCount = await fixture.providerDetection.checkAllCount()
        XCTAssertEqual(providerCheckCount, 2)
        XCTAssertEqual(lifecycle.reconciliationCount, 1)
        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testStartupActivatesScheduledTasksAfterCleanupSessionRecoveryAndProviderRefresh() async throws {
        let fixture = try AppDelegateTestFixture()
        let recorder = AppDelegateShutdownOrderRecorder()
        let sessionManager = AppDelegateStartupOrderSessionManager(recorder: recorder)
        let context = try await fixture.prepareStartupOrderingState(sessionManager: sessionManager)
        let providerDetection = AppDelegateOrderProviderDetection(recorder: recorder)
        let signalState = AppDelegateProcessSignalState(activePIDs: [100])
        let lifecycle = AppDelegateScheduledTaskLifecycleSpy()
        let appDelegate = fixture.makeStartupOrderingAppDelegate(
            recorder: recorder,
            sessionManager: sessionManager,
            providerDetection: providerDetection,
            signalState: signalState,
            scheduledTaskLifecycle: lifecycle
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await appDelegateWaitUntil("expected scheduled task activation") {
            lifecycle.activationCount == 1
        }

        XCTAssertEqual(
            recorder.values,
            [
                "stale-cleanup",
                "session-load",
                "session-orphan-cleanup",
                "provider-refresh",
                "scheduled-activation"
            ]
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testApplicationWillTerminateUsesScheduledPreparationAsSynchronousControllerFlush() async throws {
        let fixture = try AppDelegateTestFixture()
        let shutdownOrderRecorder = AppDelegateShutdownOrderRecorder()
        fixture.agentsManager.setShutdownOrderRecorder(shutdownOrderRecorder)
        let lifecycle = AppDelegateScheduledTaskLifecycleSpy(terminationOrderRecorder: shutdownOrderRecorder)
        lifecycle.terminationPreparation = ScheduledTaskTerminationPreparation(
            interruptedRunIDs: [],
            conversationIDsToTerminate: ["scheduled-conversation"],
            controllerFlushFailures: []
        )
        let fallbackFlushCalls = AppDelegateNotificationCounter()
        let appDelegate = fixture.makeAppDelegate(
            flushConversationControllers: {
                fallbackFlushCalls.increment()
                return []
            },
            teardownVoiceInput: {
                shutdownOrderRecorder.record("voice")
            },
            scheduledTaskLifecycle: lifecycle
        )

        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        XCTAssertEqual(lifecycle.terminationDates.count, 1)
        XCTAssertEqual(fallbackFlushCalls.value, 0)
        let shutdownCallCount = await fixture.agentsManager.beginShutdownCallCount()
        XCTAssertEqual(shutdownCallCount, 1)
        XCTAssertEqual(shutdownOrderRecorder.values, ["voice", "scheduled-prepare", "shutdown"])
    }
}
