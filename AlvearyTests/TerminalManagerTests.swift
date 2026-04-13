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

    func testCreateSessionSelectsNewestSessionByDefault() {
        let manager = TerminalManager()

        let first = manager.createSession(title: "Build", projectName: "Alveary", select: false)
        let second = manager.createSession(title: "Lint", projectName: "Docs")

        XCTAssertEqual(manager.sessions.map(\.id), [second, first])
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
