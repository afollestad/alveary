import AppKit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension AppDelegateTests {
    func testWakeNotificationCancelsOlderRefreshBeforeRunningProviderCheck() async throws {
        // Every value here is explicitly typed, and every call takes locals rather than nested
        // calls. `.milliseconds(_:)` is generic over `BinaryInteger`, so an integer literal fed
        // straight into a call with nine defaulted parameters left the solver resolving both at
        // once; CI measured that at 3.7s against a 3000ms budget. The lifecycle notifications are
        // hoisted for the same reason: CI later measured the one-line call-with-a-nested-call at
        // 3063ms while the same statement stayed under 100ms locally, so each statement here has
        // to stay trivial on its own. Being trivial is not a guarantee of a low reading — the
        // already-hoisted `applicationDidFinishLaunching` call below, one candidate against two
        // explicitly typed locals, has since reported 5236ms. That is the deserialization
        // attribution noise `TYPECHECK_TEST_BUDGET_MS` exists to absorb; do not restructure
        // these statements further chasing it.
        let fixture = try AppDelegateTestFixture()
        let lifecycle = AppDelegateScheduledTaskLifecycleSpy()
        let wakeRefreshDelay: Duration = .milliseconds(40)
        let launchNotification: Notification = appDelegateDidFinishLaunchingNotification()
        let terminateNotification: Notification = appDelegateWillTerminateNotification()
        let appDelegate: AppDelegate = fixture.makeAppDelegate(
            wakeRefreshDelay: wakeRefreshDelay,
            scheduledTaskLifecycle: lifecycle
        )

        appDelegate.applicationDidFinishLaunching(launchNotification)
        try await fixture.waitForProviderChecks(1, description: "expected initial startup provider detection")
        try await appDelegateWaitUntil("expected scheduled task activation after provider refresh") {
            lifecycle.activationCount == 1
        }

        let betweenWakesPause: Duration = .milliseconds(10)
        let settlePause: Duration = .milliseconds(60)
        fixture.workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try? await Task.sleep(for: betweenWakesPause)
        fixture.workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        try await fixture.waitForProviderChecks(2, description: "expected only latest wake refresh to run")
        try? await Task.sleep(for: settlePause)

        let providerCheckCount = await fixture.providerDetection.checkAllCount()
        XCTAssertEqual(providerCheckCount, 2)
        XCTAssertEqual(lifecycle.reconciliationCount, 1)
        appDelegate.applicationWillTerminate(terminateNotification)
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

        appDelegate.applicationDidFinishLaunching(appDelegateDidFinishLaunchingNotification())
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
        appDelegate.applicationWillTerminate(appDelegateWillTerminateNotification())
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

        appDelegate.applicationWillTerminate(appDelegateWillTerminateNotification())

        XCTAssertEqual(lifecycle.terminationDates.count, 1)
        XCTAssertEqual(fallbackFlushCalls.value, 0)
        let shutdownCallCount = await fixture.agentsManager.beginShutdownCallCount()
        XCTAssertEqual(shutdownCallCount, 1)
        XCTAssertEqual(shutdownOrderRecorder.values, ["voice", "scheduled-prepare", "shutdown"])
    }
}
