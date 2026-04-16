import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testEmptyThreadStateHero() {
        assertMacSnapshot(
            EmptyThreadState(
                showsRetryState: false,
                setupPhase: nil,
                isCancellingInitialSetup: false,
                error: nil,
                onRetry: {}
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_hero"
        )
    }

    func testEmptyThreadStateRetry() {
        assertMacSnapshot(
            EmptyThreadState(
                showsRetryState: true,
                setupPhase: nil,
                isCancellingInitialSetup: false,
                error: "Claude could not start because the working directory could not be prepared.",
                onRetry: {}
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_retry"
        )
    }

    func testEmptyThreadStateCreatingWorktree() {
        assertMacSnapshot(
            EmptyThreadState(
                showsRetryState: false,
                setupPhase: .creatingWorktree,
                isCancellingInitialSetup: false,
                error: nil,
                onRetry: {}
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_creating_worktree"
        )
    }

    func testEmptyThreadStateCancellingInitialSetup() {
        assertMacSnapshot(
            EmptyThreadState(
                showsRetryState: false,
                setupPhase: .creatingWorktree,
                isCancellingInitialSetup: true,
                error: nil,
                onRetry: {}
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_cancelling_initial_setup"
        )
    }
}
