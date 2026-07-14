import Foundation
import XCTest

@testable import Alveary

final class ScheduledTaskRecoveryPolicyTests: XCTestCase {
    func testTerminalRunsAreIgnored() {
        let policy = ScheduledTaskRecoveryPolicy()
        for status in [
            ScheduledTaskRunStatus.success,
            .failure,
            .interrupted,
            .skipped
        ] {
            XCTAssertEqual(
                policy.decision(
                    status: status,
                    recoveryReferenceAt: Date(timeIntervalSince1970: 0),
                    at: Date(timeIntervalSince1970: 1),
                    isSafeToResume: false
                ),
                .ignoreTerminal
            )
        }
    }

    func testClaimedRunAtInclusiveCatchUpBoundaryCanResumeWhenSafe() {
        let policy = ScheduledTaskRecoveryPolicy(maximumClaimAge: 60)

        XCTAssertEqual(
            policy.decision(
                status: .claimed,
                recoveryReferenceAt: Date(timeIntervalSince1970: 100),
                at: Date(timeIntervalSince1970: 160),
                isSafeToResume: true
            ),
            .resumeClaimed
        )
    }

    func testStaleOrUnsafeClaimedRunsAreInterruptedWithStableReasons() {
        let policy = ScheduledTaskRecoveryPolicy(maximumClaimAge: 60)

        XCTAssertEqual(
            policy.decision(
                status: .claimed,
                recoveryReferenceAt: Date(timeIntervalSince1970: 100),
                at: Date(timeIntervalSince1970: 161),
                isSafeToResume: true
            ),
            .interrupt(.claimedTooOld)
        )
        XCTAssertEqual(
            policy.decision(
                status: .claimed,
                recoveryReferenceAt: Date(timeIntervalSince1970: 100),
                at: Date(timeIntervalSince1970: 101),
                isSafeToResume: false
            ),
            .interrupt(.claimedUnsafe)
        )
        XCTAssertFalse(ScheduledTaskRecoveryInterruptionReason.claimedTooOld.message.isEmpty)
        XCTAssertFalse(ScheduledTaskRecoveryInterruptionReason.claimedUnsafe.message.isEmpty)
    }

    func testEveryInProgressExecutionStateIsInterrupted() {
        let policy = ScheduledTaskRecoveryPolicy()
        for status in [
            ScheduledTaskRunStatus.preparing,
            .running,
            .waiting
        ] {
            XCTAssertEqual(
                policy.decision(
                    status: status,
                    recoveryReferenceAt: Date(timeIntervalSince1970: 100),
                    at: Date(timeIntervalSince1970: 101),
                    isSafeToResume: true
                ),
                .interrupt(.executionWasInProgress)
            )
        }
        XCTAssertFalse(ScheduledTaskRecoveryInterruptionReason.executionWasInProgress.message.isEmpty)
    }
}
