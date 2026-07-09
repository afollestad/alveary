@preconcurrency import AppKit
import SwiftTerm
import XCTest

@testable import Alveary

@MainActor
final class TerminalViewDelegateProxyTests: XCTestCase {
    func testControllerRetainsDelegateProxyDespiteWeakTerminalDelegate() throws {
        let controller = SwiftTermTerminalSessionController(
            sessionID: UUID(),
            configuration: sampleProxyLaunchConfiguration,
            delegate: FakeTerminalSessionControllerDelegate(),
            terminationFallback: TerminalProcessTerminationFallback()
        )
        let terminalView = try XCTUnwrap(controller.view as? AlvearyLocalTerminalView)

        XCTAssertNotNil(terminalView.terminalDelegate)
    }

    func testDelegateProxyForwardsTitleAndDirectoryThroughTerminalView() {
        let terminalView = AlvearyLocalTerminalView(frame: .zero)
        let processDelegate = FakeLocalProcessTerminalViewDelegate()
        terminalView.processDelegate = processDelegate
        let proxy = TerminalViewDelegateProxy(terminalView: terminalView)

        proxy.setTerminalTitle(source: terminalView, title: "zsh")
        proxy.hostCurrentDirectoryUpdate(source: terminalView, directory: "file:///Users/alice/Project")

        XCTAssertEqual(processDelegate.title, "zsh")
        XCTAssertEqual(processDelegate.currentDirectory, "file:///Users/alice/Project")
    }

    func testDelegateProxyDeniesOSC52ClipboardAccess() {
        let terminalView = AlvearyLocalTerminalView(frame: .zero)
        let proxy = TerminalViewDelegateProxy(terminalView: terminalView)

        proxy.clipboardCopy(source: terminalView, content: Data("secret".utf8))

        XCTAssertNil(proxy.clipboardRead(source: terminalView))
    }

    func testDelegateProxyRoutesITermContentToCustomHandler() {
        let terminalView = AlvearyLocalTerminalView(frame: .zero)
        let proxy = TerminalViewDelegateProxy(terminalView: terminalView)
        var receivedContent: [UInt8] = []
        proxy.iTermContentHandler = { content in
            receivedContent = Array(content)
        }

        proxy.iTermContent(source: terminalView, content: Array("marker".utf8)[...])

        XCTAssertEqual(receivedContent, Array("marker".utf8))
    }

    func testDelegateProxyForwardsInputScrollAndRangeCallbacksThroughTerminalView() {
        let terminalView = RecordingLocalProcessTerminalView(frame: .zero)
        let proxy = TerminalViewDelegateProxy(terminalView: terminalView)
        let bytes: [UInt8] = [0x61, 0x62]

        proxy.send(source: terminalView, data: bytes[...])
        proxy.scrolled(source: terminalView, position: 0.75)
        proxy.rangeChanged(source: terminalView, startY: 2, endY: 8)

        XCTAssertEqual(terminalView.sentData, bytes)
        XCTAssertEqual(terminalView.recordedScrollPosition, 0.75)
        XCTAssertEqual(terminalView.changedRange?.startY, 2)
        XCTAssertEqual(terminalView.changedRange?.endY, 8)
    }

    func testControllerDoesNotCreateRetainCycle() {
        weak var weakController: SwiftTermTerminalSessionController?

        autoreleasepool {
            let controller = SwiftTermTerminalSessionController(
                sessionID: UUID(),
                configuration: sampleProxyLaunchConfiguration,
                delegate: FakeTerminalSessionControllerDelegate(),
                terminationFallback: TerminalProcessTerminationFallback()
            )
            weakController = controller
        }

        XCTAssertNil(weakController)
    }

    func testControllerRejectsMissingCurrentDirectoryBeforeLaunch() async {
        let delegate = RecordingLaunchFailureDelegate()
        let configuration = TerminalLaunchConfiguration(
            executable: "/bin/zsh",
            args: [],
            environment: ["TERM=xterm-256color"],
            execName: "-zsh",
            currentDirectory: "/path/that/does/not/exist"
        )
        let controller = SwiftTermTerminalSessionController(
            sessionID: UUID(),
            configuration: configuration,
            delegate: delegate,
            terminationFallback: TerminalProcessTerminationFallback()
        )

        controller.start()
        await fulfillment(of: [delegate.terminationExpectation], timeout: 1)

        XCTAssertNil(delegate.terminationExitCode)
        let terminalView = controller.view as? AlvearyLocalTerminalView
        XCTAssertFalse(terminalView?.process?.running == true)
    }

    func testCurrentDirectoryPreflightRejectsRegularFiles() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalCurrentDirectoryTests-\(UUID().uuidString)")
        try Data().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertFalse(SwiftTermTerminalSessionController.isUsableCurrentDirectory(fileURL.path))
        XCTAssertTrue(SwiftTermTerminalSessionController.isUsableCurrentDirectory(fileURL.deletingLastPathComponent().path))
    }

    func testControllerInjectsProjectActionAndKeepsInteractiveShellRunning() async throws {
        let fixture = try makeControllerActionFixture()
        defer { fixture.cleanup() }
        let delegate = RecordingTerminalDelegate()
        let controller = SwiftTermTerminalSessionController(
            sessionID: UUID(),
            configuration: fixture.configuration,
            delegate: delegate,
            terminationFallback: TerminalProcessTerminationFallback()
        )

        controller.start()
        await fulfillment(of: [delegate.completionExpectation], timeout: 5)

        let terminalView = try XCTUnwrap(controller.view as? AlvearyLocalTerminalView)
        XCTAssertEqual(delegate.projectActionExitCode, 1)
        XCTAssertTrue(terminalView.process?.running == true)

        controller.terminate()
        XCTAssertFalse(terminalView.process?.running == true)
    }
}

private extension TerminalViewDelegateProxyTests {
    func makeControllerActionFixture() throws -> ControllerActionFixture {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalControllerActionTests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
            try "export ALVEARY_TEST_ZSHENV=env\n".write(
                to: directoryURL.appendingPathComponent(".zshenv"),
                atomically: true,
                encoding: .utf8
            )
            try "export ALVEARY_TEST_ZPROFILE=profile\n".write(
                to: directoryURL.appendingPathComponent(".zprofile"),
                atomically: true,
                encoding: .utf8
            )
            try "user_precmd() { return 0 }\nprecmd_functions=(user_precmd)\nexport ALVEARY_TEST_ZSHRC=rc\n".write(
                to: directoryURL.appendingPathComponent(".zshrc"),
                atomically: true,
                encoding: .utf8
            )
            try "user_login_precmd() { return 0 }\nprecmd_functions=(user_login_precmd)\nexport ALVEARY_TEST_ZLOGIN=login\n".write(
                to: directoryURL.appendingPathComponent(".zlogin"),
                atomically: true,
                encoding: .utf8
            )
            let command = """
            if [[ "$ALVEARY_TEST_ZSHENV:$ALVEARY_TEST_ZPROFILE:$ALVEARY_TEST_ZSHRC:$ALVEARY_TEST_ZLOGIN" == "env:profile:rc:login" ]]; then
              false
            else
              (exit 42)
            fi
            """
            let configuration = TerminalLaunchConfiguration(
                executable: "/bin/zsh",
                args: [],
                environment: [
                    "HOME=\(directoryURL.path)",
                    "PATH=/usr/bin:/bin",
                    "TERM=xterm-256color",
                    "ZDOTDIR=\(directoryURL.path)"
                ],
                execName: "-zsh",
                currentDirectory: directoryURL.path,
                projectActionCommand: command
            )
            return ControllerActionFixture(directoryURL: directoryURL, configuration: configuration)
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
    }
}

private final class RecordingLocalProcessTerminalView: LocalProcessTerminalView {
    private(set) var sentData: [UInt8] = []
    private(set) var recordedScrollPosition: Double?
    private(set) var changedRange: (startY: Int, endY: Int)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sentData = Array(data)
    }

    override func scrolled(source: TerminalView, position: Double) {
        recordedScrollPosition = position
    }

    override func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        changedRange = (startY, endY)
    }
}

private struct ControllerActionFixture {
    let directoryURL: URL
    let configuration: TerminalLaunchConfiguration

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private let sampleProxyLaunchConfiguration = TerminalLaunchConfiguration(
    executable: "/bin/zsh",
    args: [],
    environment: ["TERM=xterm-256color"],
    execName: "-zsh",
    currentDirectory: "/Users/alice"
)

@MainActor
private final class FakeTerminalSessionControllerDelegate: TerminalSessionControllerDelegate {
    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didTerminateSession id: UUID,
        exitCode: Int32?
    ) {}

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didCompleteProjectAction id: UUID,
        exitCode: Int32
    ) {}

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didUpdateTitle title: String,
        forSession id: UUID
    ) {}

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didUpdateCurrentDirectory currentDirectory: String,
        forSession id: UUID
    ) {}
}

@MainActor
private final class RecordingTerminalDelegate: TerminalSessionControllerDelegate {
    let completionExpectation = XCTestExpectation(description: "Project action completed")
    private(set) var projectActionExitCode: Int32?

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didTerminateSession id: UUID,
        exitCode: Int32?
    ) {}

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didCompleteProjectAction id: UUID,
        exitCode: Int32
    ) {
        projectActionExitCode = exitCode
        completionExpectation.fulfill()
    }

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didUpdateTitle title: String,
        forSession id: UUID
    ) {}

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didUpdateCurrentDirectory currentDirectory: String,
        forSession id: UUID
    ) {}
}

@MainActor
private final class RecordingLaunchFailureDelegate: TerminalSessionControllerDelegate {
    let terminationExpectation = XCTestExpectation(description: "Terminal launch failed")
    private(set) var terminationExitCode: Int32?

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didTerminateSession id: UUID,
        exitCode: Int32?
    ) {
        terminationExitCode = exitCode
        terminationExpectation.fulfill()
    }

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didCompleteProjectAction id: UUID,
        exitCode: Int32
    ) {}

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didUpdateTitle title: String,
        forSession id: UUID
    ) {}

    func terminalSessionController(
        _ controller: any TerminalSessionControlling,
        didUpdateCurrentDirectory currentDirectory: String,
        forSession id: UUID
    ) {}
}

@MainActor
private final class FakeLocalProcessTerminalViewDelegate: @preconcurrency LocalProcessTerminalViewDelegate {
    private(set) var title: String?
    private(set) var currentDirectory: String?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        self.title = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        currentDirectory = directory
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {}
}
