import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppDelegateTests {
    func testCollectiveReviewShutdownCompletesBeforeProviderShutdown() throws {
        let fixture = try AppDelegateTestFixture()
        let recorder = AppDelegateShutdownOrderRecorder()
        fixture.agentsManager.setShutdownOrderRecorder(recorder)
        let delegate = fixture.makeAppDelegate(prepareCollectiveReviewsForTermination: {
            recorder.record("collective-prepare-and-stop")
        })

        delegate.applicationWillTerminate(appDelegateWillTerminateNotification())

        XCTAssertEqual(recorder.values, ["collective-prepare-and-stop", "shutdown"])
    }

    func testCollectiveReviewWorkControlsSuddenTerminationAndRecoversAtLaunch() async throws {
        let fixture = try AppDelegateTestFixture()
        let disabled = AppDelegateNotificationCounter()
        let enabled = AppDelegateNotificationCounter()
        let recovered = AppDelegateNotificationCounter()
        let state = CollectiveWorkState()
        let delegate = fixture.makeAppDelegate(
            disableSuddenTermination: { disabled.increment() },
            enableSuddenTermination: { enabled.increment() },
            recoverCollectiveReviews: { recovered.increment() },
            hasCollectiveReviewWork: { state.isWorking }
        )

        delegate.applicationDidFinishLaunching(appDelegateDidFinishLaunchingNotification())
        try await appDelegateWaitUntil("collective recovery after discovery") { recovered.value == 1 }
        state.isWorking = true
        fixture.appNotificationCenter.post(name: .pullRequestReviewRunsChanged, object: nil)
        XCTAssertEqual(disabled.value, 1)
        state.isWorking = false
        fixture.appNotificationCenter.post(name: .pullRequestReviewWorkerProcessesChanged, object: nil)
        XCTAssertEqual(enabled.value, 1)
        delegate.applicationWillTerminate(appDelegateWillTerminateNotification())
    }
}

@MainActor
private final class CollectiveWorkState {
    var isWorking = false
}
