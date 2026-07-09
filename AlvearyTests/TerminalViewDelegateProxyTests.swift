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
