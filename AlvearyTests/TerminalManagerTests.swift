@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class TerminalManagerTests: XCTestCase {
    func testChipLabelIncludesThreadNameWhenPresent() {
        let session = TerminalSession(title: "Run", threadName: "Terminal polish")

        XCTAssertEqual(session.chipLabel, "Run - Terminal polish")
    }

    func testShellChipLabelHidesRawTerminalTitle() {
        let session = TerminalSession(
            kind: .shell,
            title: "alice@MacBook-Pro:~/Documents/worktrees/project/feature",
            threadName: "New thread"
        )

        XCTAssertEqual(session.chipLabel, "Shell - New thread")
    }

    func testShellChipLabelWithoutThreadContextIsShell() {
        let session = TerminalSession(
            kind: .shell,
            title: "alice@MacBook-Pro:~/Documents/worktrees/project/feature"
        )

        XCTAssertEqual(session.chipLabel, "Shell")
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

        let first = manager.createSession(title: "Build", select: false)
        let second = manager.createSession(title: "Lint")

        XCTAssertEqual(manager.sessions.map(\.id), [first, second])
        XCTAssertEqual(manager.selectedSessionID, second)
        XCTAssertEqual(manager.selectedSession?.title, "Lint")
    }

    func testCreateSessionCreatesStartsAndFocusesControllerWhenConfigured() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)

        let sessionID = manager.createSession(
            kind: .shell,
            title: "Shell",
            focus: true,
            launchConfiguration: sampleLaunchConfiguration
        )
        let controller = try XCTUnwrap(factory.controllers[sessionID])

        XCTAssertEqual(controller.configuration, sampleLaunchConfiguration)
        XCTAssertEqual(controller.startCallCount, 1)
        XCTAssertEqual(controller.focusCallCount, 1)
        XCTAssertTrue(manager.controller(for: sessionID) === controller)
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

    func testCloseSessionTerminatesAndRemovesController() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)
        let sessionID = manager.createSession(title: "Build", launchConfiguration: sampleLaunchConfiguration)
        let controller = try XCTUnwrap(factory.controllers[sessionID])

        manager.closeSession(id: sessionID)

        XCTAssertEqual(controller.terminateCallCount, 1)
        XCTAssertNil(manager.controller(for: sessionID))
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

    func testCreateSessionPruningTerminatesOldestController() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)
        let first = manager.createSession(title: "First", maxSessions: 1, launchConfiguration: sampleLaunchConfiguration)
        let firstController = try XCTUnwrap(factory.controllers[first])

        let second = manager.createSession(title: "Second", maxSessions: 1, launchConfiguration: sampleLaunchConfiguration)

        XCTAssertEqual(firstController.terminateCallCount, 1)
        XCTAssertEqual(manager.sessions.map(\.id), [second])
        XCTAssertEqual(manager.runningProjectActionSessionIDs, [second])
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

    func testControllerTerminationNilExitCodeMarksFailure() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)
        let sessionID = manager.createSession(title: "Build", launchConfiguration: sampleLaunchConfiguration)
        let controller = try XCTUnwrap(factory.controllers[sessionID])

        controller.finish(exitCode: nil)

        XCTAssertEqual(manager.sessions.first(where: { $0.id == sessionID })?.status, .failed)
        XCTAssertNotNil(manager.sessions.first(where: { $0.id == sessionID })?.endedAt)
    }

    func testProjectActionCompletionMarksStatusWhileShellRemainsLive() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)
        let sessionID = manager.createSession(
            kind: .projectAction,
            title: "Build",
            currentDirectory: "/tmp/original",
            launchConfiguration: sampleLaunchConfiguration
        )
        let controller = try XCTUnwrap(factory.controllers[sessionID])

        controller.completeProjectAction(exitCode: 0)
        controller.updateCurrentDirectory("/tmp/after-action")

        let session = try XCTUnwrap(manager.sessions.first(where: { $0.id == sessionID }))
        XCTAssertEqual(session.status, .succeeded)
        XCTAssertNotNil(session.endedAt)
        XCTAssertEqual(session.currentDirectory, "/tmp/after-action")
        XCTAssertNotNil(manager.controller(for: sessionID))
    }

    func testLaterShellExitDoesNotReplaceCompletedProjectActionOutcome() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)
        let sessionID = manager.createSession(
            kind: .projectAction,
            title: "Build",
            launchConfiguration: sampleLaunchConfiguration
        )
        let controller = try XCTUnwrap(factory.controllers[sessionID])

        controller.completeProjectAction(exitCode: 0)
        controller.finish(exitCode: 1)

        XCTAssertEqual(manager.sessions.first(where: { $0.id == sessionID })?.status, .succeeded)
    }

    func testLateControllerTerminationForRemovedSessionIsIgnored() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)
        let sessionID = manager.createSession(title: "Build", launchConfiguration: sampleLaunchConfiguration)
        let controller = try XCTUnwrap(factory.controllers[sessionID])

        manager.closeSession(id: sessionID)
        controller.finish(exitCode: 1)

        XCTAssertTrue(manager.sessions.isEmpty)
    }

    func testLateControllerTerminationForCancelledSessionIsIgnored() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)
        let sessionID = manager.createSession(
            kind: .shell,
            title: "Build",
            launchConfiguration: sampleLaunchConfiguration
        )
        let controller = try XCTUnwrap(factory.controllers[sessionID])

        manager.cancelSession(id: sessionID)
        controller.finish(exitCode: 0)
        controller.updateTitle("late title")
        controller.updateCurrentDirectory("/tmp/late")

        let session = try XCTUnwrap(manager.sessions.first(where: { $0.id == sessionID }))
        XCTAssertEqual(session.status, .cancelled)
        XCTAssertEqual(session.title, "Build")
        XCTAssertNil(session.currentDirectory)
    }

    func testControllerTitleUpdatesShellSessionsOnly() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)
        let shellID = manager.createSession(
            kind: .shell,
            title: "Shell",
            launchConfiguration: sampleLaunchConfiguration
        )
        let projectActionID = manager.createSession(
            kind: .projectAction,
            title: "Build",
            launchConfiguration: sampleLaunchConfiguration
        )

        try XCTUnwrap(factory.controllers[shellID]).updateTitle("zsh")
        try XCTUnwrap(factory.controllers[projectActionID]).updateTitle("npm test")

        XCTAssertEqual(manager.sessions.first(where: { $0.id == shellID })?.title, "zsh")
        XCTAssertEqual(manager.sessions.first(where: { $0.id == shellID })?.chipLabel, "Shell")
        XCTAssertEqual(manager.sessions.first(where: { $0.id == projectActionID })?.title, "Build")
    }

    func testControllerDirectoryUpdatesMetadata() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)
        let sessionID = manager.createSession(title: "Build", launchConfiguration: sampleLaunchConfiguration)

        try XCTUnwrap(factory.controllers[sessionID]).updateCurrentDirectory("/tmp/project")

        XCTAssertEqual(manager.sessions.first(where: { $0.id == sessionID })?.currentDirectory, "/tmp/project")
    }

    func testLateControllerMetadataUpdatesForFinishedSessionAreIgnored() throws {
        let factory = FakeTerminalControllerFactory()
        let manager = TerminalManager(controllerFactory: factory)
        let sessionID = manager.createSession(
            kind: .shell,
            title: "Shell",
            currentDirectory: "/tmp/original",
            launchConfiguration: sampleLaunchConfiguration
        )
        let controller = try XCTUnwrap(factory.controllers[sessionID])

        controller.finish(exitCode: 0)
        controller.updateTitle("late title")
        controller.updateCurrentDirectory("/tmp/late")

        let session = try XCTUnwrap(manager.sessions.first(where: { $0.id == sessionID }))
        XCTAssertEqual(session.status, .succeeded)
        XCTAssertEqual(session.title, "Shell")
        XCTAssertEqual(session.currentDirectory, "/tmp/original")
    }

    func testRunningProjectActionSessionIDsIgnoreShellAndFinishedSessions() {
        let manager = TerminalManager()
        _ = manager.createSession(kind: .shell, title: "Shell")
        let projectActionID = manager.createSession(kind: .projectAction, title: "Build")
        _ = manager.createSession(kind: .projectAction, title: "Finished", status: .succeeded)

        XCTAssertEqual(manager.runningProjectActionSessionIDs, [projectActionID])
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

    func testTerminalToolbarCompletionOutcomeFailsWhenAnyLiveProjectActionSessionFailed() {
        let manager = TerminalManager()
        _ = manager.createSession(kind: .projectAction, title: "Previous failure", status: .failed)
        let successID = manager.createSession(kind: .projectAction, title: "Current success", status: .succeeded)

        let outcome = TerminalToolbarCompletionOutcome.outcome(
            completedSessionIDs: [successID],
            terminalManager: manager
        )

        XCTAssertEqual(outcome, .failed)
    }

    func testTerminalToolbarCompletionOutcomeIgnoresFailedShellSessions() {
        let manager = TerminalManager()
        _ = manager.createSession(kind: .shell, title: "Exited shell", status: .failed)
        let successID = manager.createSession(kind: .projectAction, title: "Current success", status: .succeeded)

        let outcome = TerminalToolbarCompletionOutcome.outcome(
            completedSessionIDs: [successID],
            terminalManager: manager
        )

        XCTAssertEqual(outcome, .succeeded)
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

private let sampleLaunchConfiguration = TerminalLaunchConfiguration(
    executable: "/bin/zsh",
    args: [],
    environment: ["HOME=/Users/alice", "TERM=xterm-256color"],
    execName: "-zsh",
    currentDirectory: "/Users/alice"
)

@MainActor
private final class FakeTerminalControllerFactory: TerminalSessionControllerFactory {
    private(set) var controllers: [UUID: FakeTerminalController] = [:]

    func makeController(
        sessionID: UUID,
        configuration: TerminalLaunchConfiguration,
        delegate: any TerminalSessionControllerDelegate
    ) -> any TerminalSessionControlling {
        let controller = FakeTerminalController(
            sessionID: sessionID,
            configuration: configuration,
            delegate: delegate
        )
        controllers[sessionID] = controller
        return controller
    }
}

@MainActor
private final class FakeTerminalController: TerminalSessionControlling {
    let sessionID: UUID
    let configuration: TerminalLaunchConfiguration
    let view = NSView()

    private weak var delegate: (any TerminalSessionControllerDelegate)?
    private(set) var startCallCount = 0
    private(set) var terminateCallCount = 0
    private(set) var focusCallCount = 0
    private(set) var reapplyThemeCallCount = 0

    init(
        sessionID: UUID,
        configuration: TerminalLaunchConfiguration,
        delegate: any TerminalSessionControllerDelegate
    ) {
        self.sessionID = sessionID
        self.configuration = configuration
        self.delegate = delegate
    }

    func start() {
        startCallCount += 1
    }

    func terminate() {
        terminateCallCount += 1
    }

    func requestFocus() {
        focusCallCount += 1
    }

    func reapplyTheme() {
        reapplyThemeCallCount += 1
    }

    func finish(exitCode: Int32?) {
        delegate?.terminalSessionController(self, didTerminateSession: sessionID, exitCode: exitCode)
    }

    func completeProjectAction(exitCode: Int32) {
        delegate?.terminalSessionController(
            self,
            didCompleteProjectAction: sessionID,
            exitCode: exitCode
        )
    }

    func updateTitle(_ title: String) {
        delegate?.terminalSessionController(self, didUpdateTitle: title, forSession: sessionID)
    }

    func updateCurrentDirectory(_ currentDirectory: String) {
        delegate?.terminalSessionController(
            self,
            didUpdateCurrentDirectory: currentDirectory,
            forSession: sessionID
        )
    }
}
