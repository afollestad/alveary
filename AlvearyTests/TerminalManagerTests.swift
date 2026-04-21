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
}
