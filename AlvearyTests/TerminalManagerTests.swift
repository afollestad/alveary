import XCTest

@testable import Alveary

@MainActor
final class TerminalManagerTests: XCTestCase {
    func testChipLabelIncludesThreadNameWhenPresent() {
        let session = TerminalSession(title: "Run", threadName: "Terminal polish")

        XCTAssertEqual(session.chipLabel, "Run - Terminal polish")
    }

    func testChipLabelTruncatesLongThreadNames() {
        let session = TerminalSession(title: "Run", threadName: "01234567890123456789-extra")

        XCTAssertEqual(session.chipLabel, "Run - 01234567890123456789…")
    }

    func testChipLabelDoesNotCountInlineCodeDelimitersTowardTruncationLimit() {
        // 20 visible chars (backticks excluded): "Test " + "code" + " Rendering" = 19.
        let session = TerminalSession(title: "Run", threadName: "Test `code` Rendering")

        XCTAssertEqual(session.chipLabel, "Run - Test `code` Rendering")
    }

    func testChipLabelClosesInlineCodeSpanWhenTruncatingInsideIt() {
        // Visible budget (20) is spent on "Really long code blo" — 12 chars before the
        // code span, then 8 chars inside it. The truncation falls inside the code span,
        // so a closing backtick is emitted so the surviving markdown still renders a chip.
        let session = TerminalSession(title: "Run", threadName: "Really long `code block` stuff")

        XCTAssertEqual(session.chipLabel, "Run - Really long `code blo`…")
    }

    func testChipLabelClosesMultiBacktickInlineCodeSpanWithMatchingDelimiterLength() {
        // Double-backtick span means the surviving markdown must close with two backticks
        // to keep the delimiters balanced; a single backtick would leave the fragment
        // unable to render as a chip.
        let session = TerminalSession(title: "Run", threadName: "Start ``inside code block here`` end")

        XCTAssertEqual(session.chipLabel, "Run - Start ``inside code bl``…")
    }

    func testChipLabelCountsEmojiAsSingleGraphemeClusterAgainstBudget() {
        // Each 🔥 is one grapheme cluster but two UTF-16 code units. Budget is 20
        // grapheme clusters, so 20 🔥 should fit without truncation.
        let name = String(repeating: "🔥", count: 20)
        let session = TerminalSession(title: "Run", threadName: name)

        XCTAssertEqual(session.chipLabel, "Run - \(name)")
    }

    func testChipLabelTruncatesAtGraphemeClusterBoundaryForEmoji() {
        // 21 🔥 exceeds the 20-grapheme budget. The cut must land on a grapheme boundary
        // so the surviving string never breaks a surrogate pair.
        let session = TerminalSession(title: "Run", threadName: String(repeating: "🔥", count: 21))

        XCTAssertEqual(session.chipLabel, "Run - \(String(repeating: "🔥", count: 20))…")
    }

    func testCreateSessionSelectsNewestSessionByDefault() {
        let manager = TerminalManager()

        let first = manager.createSession(title: "Build", projectName: "Alveary", select: false)
        let second = manager.createSession(title: "Lint", projectName: "Docs")

        XCTAssertEqual(manager.sessions.map(\.id), [first, second])
        XCTAssertEqual(manager.selectedSessionID, second)
        XCTAssertEqual(manager.selectedSession?.title, "Lint")
    }

    func testCloseSessionFallsBackToNextAvailableSession() {
        let manager = TerminalManager()

        let first = manager.createSession(title: "Build", select: false)
        let second = manager.createSession(title: "Lint")

        manager.closeSession(id: second)

        XCTAssertEqual(manager.sessions.map(\.id), [first])
        XCTAssertEqual(manager.selectedSessionID, first)
    }

    func testCloseSelectedMiddleSessionPicksNextNeighbor() {
        let manager = TerminalManager()

        let first = manager.createSession(title: "A", select: false)
        let second = manager.createSession(title: "B")
        let third = manager.createSession(title: "C", select: false)
        manager.selectSession(id: second)

        manager.closeSession(id: second)

        XCTAssertEqual(manager.sessions.map(\.id), [first, third])
        XCTAssertEqual(manager.selectedSessionID, third)
    }

    func testCloseNonSelectedSessionPreservesSelection() {
        let manager = TerminalManager()

        let first = manager.createSession(title: "A", select: false)
        let second = manager.createSession(title: "B")

        manager.closeSession(id: first)

        XCTAssertEqual(manager.sessions.map(\.id), [second])
        XCTAssertEqual(manager.selectedSessionID, second)
    }

    func testCloseSessionCancelsRegisteredTask() {
        let manager = TerminalManager()
        let sessionID = manager.createSession(title: "Build")
        let task = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(10))
        }

        manager.registerTask(task, forSessionID: sessionID)
        manager.closeSession(id: sessionID)

        XCTAssertTrue(task.isCancelled)
        XCTAssertTrue(manager.sessions.isEmpty)
    }

    func testCreateSessionPrunesChronologicallyOldestSessionOverLimit() {
        let manager = TerminalManager()
        let first = manager.createSession(
            title: "First",
            startedAt: Date(timeIntervalSince1970: 1),
            maxSessions: 2
        )
        let second = manager.createSession(
            title: "Second",
            startedAt: Date(timeIntervalSince1970: 3),
            maxSessions: 2
        )
        let third = manager.createSession(
            title: "Third",
            startedAt: Date(timeIntervalSince1970: 2),
            maxSessions: 2
        )

        XCTAssertEqual(manager.sessions.map(\.id), [second, third])
        XCTAssertFalse(manager.sessions.contains(where: { $0.id == first }))
        XCTAssertEqual(manager.selectedSessionID, third)
    }

    func testCreateSessionPruningCancelsOldestRunningTask() {
        let manager = TerminalManager()
        let first = manager.createSession(title: "First", maxSessions: 1)
        let task = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(10))
        }
        manager.registerTask(task, forSessionID: first)

        let second = manager.createSession(title: "Second", maxSessions: 1)

        XCTAssertTrue(task.isCancelled)
        XCTAssertEqual(manager.sessions.map(\.id), [second])
        XCTAssertEqual(manager.runningSessionIDs, [second])
    }

    func testAppendOutputRetainsNewestContentWithinBound() {
        let manager = TerminalManager()
        let sessionID = manager.createSession(title: "Build")
        let output = String(repeating: "1234567890", count: 13_000)

        manager.appendOutput(output, to: sessionID)

        XCTAssertEqual(manager.selectedSession?.output.count, 120_000)
        XCTAssertTrue(manager.selectedSession?.output.hasSuffix("1234567890") == true)
    }

    func testMarkSessionFinishedUpdatesStatusAndEndTime() {
        let manager = TerminalManager()
        let successID = manager.createSession(title: "Build")
        let failureID = manager.createSession(title: "Test")

        manager.markSessionFinished(id: successID, exitCode: 0)
        manager.markSessionFinished(id: failureID, exitCode: 1)

        XCTAssertEqual(manager.sessions.first(where: { $0.id == successID })?.status, .succeeded)
        XCTAssertEqual(manager.sessions.first(where: { $0.id == failureID })?.status, .failed)
        XCTAssertNotNil(manager.sessions.first(where: { $0.id == successID })?.endedAt)
        XCTAssertNotNil(manager.sessions.first(where: { $0.id == failureID })?.endedAt)
    }

    func testRunningSessionIDsTrackRunningSessionsOnly() {
        let manager = TerminalManager()
        let runningID = manager.createSession(title: "Build")
        let succeededID = manager.createSession(title: "Lint", status: .succeeded)
        let failedID = manager.createSession(title: "Test", status: .failed)
        let cancelledID = manager.createSession(title: "Run", status: .cancelled)

        XCTAssertEqual(manager.runningSessionIDs, [runningID])
        XCTAssertTrue(manager.hasRunningSession)
        XCTAssertFalse(manager.sessions.first(where: { $0.id == succeededID })?.isRunning == true)
        XCTAssertFalse(manager.sessions.first(where: { $0.id == failedID })?.isRunning == true)
        XCTAssertFalse(manager.sessions.first(where: { $0.id == cancelledID })?.isRunning == true)
    }

    func testHasRunningSessionTurnsFalseWhenAllSessionsFinish() {
        let manager = TerminalManager()
        let firstID = manager.createSession(title: "Build")
        let secondID = manager.createSession(title: "Test")

        manager.markSessionFinished(id: firstID, exitCode: 0)
        XCTAssertTrue(manager.hasRunningSession)

        manager.markSessionFinished(id: secondID, exitCode: 0)
        XCTAssertFalse(manager.hasRunningSession)
        XCTAssertTrue(manager.runningSessionIDs.isEmpty)
    }

    func testCompletionOutcomeForSessions() {
        let manager = TerminalManager()
        let successID = manager.createSession(title: "Build", status: .succeeded)
        let failureID = manager.createSession(title: "Test", status: .failed)
        let cancelledID = manager.createSession(title: "Run", status: .cancelled)

        XCTAssertEqual(manager.completionOutcome(for: [successID]), .succeeded)
        XCTAssertEqual(manager.completionOutcome(for: [successID, failureID]), .failed)
        XCTAssertEqual(manager.completionOutcome(for: [successID, cancelledID]), .cancelled)
        XCTAssertEqual(manager.completionOutcome(for: [successID, failureID, cancelledID]), .failed)
    }

    func testTerminalToolbarCompletionOutcomeFailsWhenAnyLiveSessionFailed() {
        let manager = TerminalManager()
        _ = manager.createSession(title: "Previous failure", status: .failed)
        let successID = manager.createSession(title: "Current success", status: .succeeded)

        let outcome = TerminalToolbarCompletionOutcome.outcome(
            completedSessionIDs: [successID],
            terminalManager: manager
        )

        XCTAssertEqual(outcome, .failed)
    }

    func testCompletionOutcomeRequiresKnownNonRunningSessions() {
        let manager = TerminalManager()
        let runningID = manager.createSession(title: "Build")
        let successID = manager.createSession(title: "Lint", status: .succeeded)

        XCTAssertNil(manager.completionOutcome(for: []))
        XCTAssertNil(manager.completionOutcome(for: [runningID]))
        XCTAssertNil(manager.completionOutcome(for: [successID, UUID()]))
    }
}
