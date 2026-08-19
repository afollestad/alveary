import XCTest

@testable import Alveary

/// `ThreadStatus.folded` is a pure fold over `ConversationStatusSnapshot` values — no `@Model`
/// crosses its boundary, which is the deleted-row safety contract
/// `DeletedModelRenderSafetyTests` locks in. These tests cover the precedence — archived, busy,
/// waiting/decision, error, unread, stopped — in the single-snapshot (tab chip) and
/// multi-snapshot (sidebar row) forms.
final class ThreadStatusTests: XCTestCase {
    func testSingleConversationBusyWinsOverUnread() {
        XCTAssertEqual(folded([.init(isUnread: true, runtime: .busy)]), .busy)
    }

    func testSingleConversationWaitingForUserWinsOverUnread() {
        XCTAssertEqual(folded([.init(isUnread: true, runtime: .waitingForUser)]), .waitingForUser)
    }

    func testSingleConversationErrorWinsOverUnread() {
        XCTAssertEqual(folded([.init(isUnread: true, runtime: .error)]), .error)
    }

    func testSingleConversationUnreadWhenIdle() {
        XCTAssertEqual(folded([.init(isUnread: true, runtime: .idle)]), .unread)
    }

    func testSingleConversationStoppedWhenReadAndNeutral() {
        XCTAssertEqual(folded([.init(isUnread: false)]), .stopped)
    }

    func testSingleConversationArchivedOverridesAll() {
        XCTAssertEqual(folded([.init(isUnread: true, runtime: .busy)], isArchived: true), .archived)
    }

    // MARK: - Pending decisions

    /// The green-to-blue upgrade: a queued scheduling proposal marks its conversation unread, and
    /// green already means "done".
    func testSingleConversationPendingDecisionWinsOverUnread() {
        XCTAssertEqual(folded([.init(isUnread: true, runtime: .idle, awaitsDecision: true)]), .waitingForUser)
    }

    func testSingleConversationPendingDecisionWinsOverError() {
        XCTAssertEqual(folded([.init(runtime: .error, awaitsDecision: true)]), .waitingForUser)
    }

    func testSingleConversationBusyWinsOverPendingDecision() {
        XCTAssertEqual(folded([.init(runtime: .busy, awaitsDecision: true)]), .busy)
    }

    func testSingleConversationArchivedOverridesPendingDecision() {
        XCTAssertEqual(folded([.init(awaitsDecision: true)], isArchived: true), .archived)
    }

    func testThreadWaitingOnPendingDecisionInAnyConversation() {
        XCTAssertEqual(
            folded([
                .init(),
                .init(awaitsDecision: true)
            ]),
            .waitingForUser
        )
    }

    func testThreadBusyPreferredOverPendingDecision() {
        XCTAssertEqual(
            folded([
                .init(awaitsDecision: true),
                .init(runtime: .busy)
            ]),
            .busy
        )
    }

    func testThreadPendingDecisionPreferredOverErrorAndUnread() {
        XCTAssertEqual(
            folded([
                .init(isUnread: true),
                .init(runtime: .error),
                .init(awaitsDecision: true)
            ]),
            .waitingForUser
        )
    }

    func testThreadBusyOnAnyBusyConversation() {
        XCTAssertEqual(
            folded([
                .init(isUnread: true),
                .init(runtime: .busy),
                .init()
            ]),
            .busy
        )
    }

    func testThreadErrorPreferredOverUnread() {
        XCTAssertEqual(
            folded([
                .init(isUnread: true),
                .init(runtime: .error)
            ]),
            .error
        )
    }

    func testThreadWaitingForUserPreferredOverErrorAndUnread() {
        XCTAssertEqual(
            folded([
                .init(isUnread: true),
                .init(runtime: .error),
                .init(runtime: .waitingForUser)
            ]),
            .waitingForUser
        )
    }

    func testThreadBusyPreferredOverWaitingForUser() {
        XCTAssertEqual(
            folded([
                .init(runtime: .waitingForUser),
                .init(runtime: .busy)
            ]),
            .busy
        )
    }

    func testThreadUnreadWhenAnyConversationUnread() {
        XCTAssertEqual(
            folded([
                .init(),
                .init(isUnread: true),
                .init()
            ]),
            .unread
        )
    }

    func testThreadStoppedWhenAllReadAndNeutral() {
        XCTAssertEqual(folded([.init(), .init()]), .stopped)
    }

    func testThreadArchivedOverridesUnread() {
        XCTAssertEqual(folded([.init(isUnread: true, runtime: .busy)], isArchived: true), .archived)
    }

    func testThreadStoppedWithNoConversations() {
        XCTAssertEqual(folded([]), .stopped)
    }

    // MARK: - Durable failures

    /// The regression this exists for: a provider that errors without ending its turn leaves the
    /// runtime reporting `.busy`, which used to short-circuit the fold and hide the failure.
    func testDurableFailureBeatsItsOwnStaleBusySignal() {
        XCTAssertEqual(folded([.init(runtime: .busy, lastTurnFailed: true)]), .error)
    }

    /// Only the failed conversation forfeits its `.busy`; a sibling doing real work still spins.
    func testLiveBusyInASiblingConversationStillWins() {
        XCTAssertEqual(
            folded([
                .init(lastTurnFailed: true),
                .init(runtime: .busy)
            ]),
            .busy
        )
    }

    /// The relaunch case: the in-memory signal is gone, the persisted failure is not.
    func testDurableFailureShowsErrorWithNeutralRuntime() {
        XCTAssertEqual(folded([.init(lastTurnFailed: true)]), .error)
    }

    func testWaitingForUserStillBeatsDurableFailure() {
        XCTAssertEqual(
            folded([
                .init(lastTurnFailed: true),
                .init(runtime: .waitingForUser)
            ]),
            .waitingForUser
        )
    }

    func testDurableFailureBeatsUnread() {
        XCTAssertEqual(folded([.init(isUnread: true, lastTurnFailed: true)]), .error)
    }

    func testArchivedOverridesDurableFailure() {
        XCTAssertEqual(folded([.init(lastTurnFailed: true)], isArchived: true), .archived)
    }

    private struct ConversationSpec {
        var isUnread = false
        var runtime: ActivitySignal = .neutral
        var awaitsDecision = false
        var lastTurnFailed = false
    }

    private func folded(_ specs: [ConversationSpec], isArchived: Bool = false) -> ThreadStatus {
        var runtimeByConversationID: [String: ActivitySignal] = [:]
        let snapshots = specs.enumerated().map { index, spec -> ConversationStatusSnapshot in
            let conversationID = "conversation-\(index)"
            runtimeByConversationID[conversationID] = spec.runtime
            return ConversationStatusSnapshot(
                conversationID: conversationID,
                isUnread: spec.isUnread,
                awaitsUserDecision: spec.awaitsDecision,
                lastTurnFailed: spec.lastTurnFailed
            )
        }
        return .folded(isArchived: isArchived, conversations: snapshots) {
            runtimeByConversationID[$0] ?? .neutral
        }
    }
}
