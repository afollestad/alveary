@preconcurrency import AppKit
import Foundation
import SwiftTerm

@MainActor
final class SwiftTermTerminalControllerFactory: TerminalSessionControllerFactory {
    private let terminationFallback: TerminalProcessTerminationFallback

    init(terminationFallback: TerminalProcessTerminationFallback = TerminalProcessTerminationFallback()) {
        self.terminationFallback = terminationFallback
    }

    func makeController(
        sessionID: UUID,
        configuration: TerminalLaunchConfiguration,
        delegate: any TerminalSessionControllerDelegate
    ) -> any TerminalSessionControlling {
        SwiftTermTerminalSessionController(
            sessionID: sessionID,
            configuration: configuration,
            delegate: delegate,
            terminationFallback: terminationFallback
        )
    }
}

@MainActor
final class SwiftTermTerminalSessionController: NSObject, TerminalSessionControlling {
    let sessionID: UUID
    let configuration: TerminalLaunchConfiguration

    private weak var delegate: (any TerminalSessionControllerDelegate)?
    private let terminalView: AlvearyLocalTerminalView
    private let delegateProxy: TerminalViewDelegateProxy
    private let terminationFallback: TerminalProcessTerminationFallback
    private var didStart = false

    var view: NSView {
        terminalView
    }

    init(
        sessionID: UUID,
        configuration: TerminalLaunchConfiguration,
        delegate: any TerminalSessionControllerDelegate,
        terminationFallback: TerminalProcessTerminationFallback
    ) {
        let terminalView = AlvearyLocalTerminalView(frame: .zero)
        self.sessionID = sessionID
        self.configuration = configuration
        self.delegate = delegate
        self.terminalView = terminalView
        self.delegateProxy = TerminalViewDelegateProxy(terminalView: terminalView)
        self.terminationFallback = terminationFallback
        super.init()

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.onAppearanceChanged = { [weak self] in
            self?.reapplyTheme()
        }
        terminalView.terminalDelegate = delegateProxy
        terminalView.processDelegate = self
        reapplyTheme()
    }

    func start() {
        guard !didStart else {
            return
        }

        didStart = true
        reapplyTheme()
        terminalView.startProcess(
            executable: configuration.executable,
            args: configuration.args,
            environment: configuration.environment,
            execName: configuration.execName,
            currentDirectory: configuration.currentDirectory
        )
    }

    func terminate() {
        let pid = terminalView.process?.shellPid ?? 0
        terminalView.terminate()
        terminationFallback.schedule(pid: pid)
    }

    func requestFocus() {
        terminalView.requestTerminalFocus()
    }

    func reapplyTheme() {
        TerminalThemePalette.resolved(for: terminalView.effectiveAppearance).apply(to: terminalView)
    }
}

extension SwiftTermTerminalSessionController: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // The retained `TerminalViewDelegateProxy` already called the view's own
        // `sizeChanged` implementation, which updates the PTY window size before
        // SwiftTerm reposts this process-level callback.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        delegate?.terminalSessionController(self, didUpdateTitle: title, forSession: sessionID)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let currentDirectory = Self.normalizedCurrentDirectory(from: directory) else {
            return
        }

        delegate?.terminalSessionController(
            self,
            didUpdateCurrentDirectory: currentDirectory,
            forSession: sessionID
        )
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        delegate?.terminalSessionController(self, didTerminateSession: sessionID, exitCode: exitCode)
    }

    static func normalizedCurrentDirectory(from directory: String?) -> String? {
        guard let trimmedDirectory = directory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedDirectory.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmedDirectory),
           url.isFileURL {
            return url.path
        }

        guard trimmedDirectory.hasPrefix("/") else {
            return nil
        }

        return trimmedDirectory
    }
}

final class AlvearyLocalTerminalView: LocalProcessTerminalView {
    var onAppearanceChanged: (() -> Void)?

    private var hasPendingFocusRequest = false

    override func mouseDown(with event: NSEvent) {
        focusIfPossible()
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onAppearanceChanged?()
        consumePendingFocusRequestIfPossible()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }

    func requestTerminalFocus() {
        hasPendingFocusRequest = true
        consumePendingFocusRequestIfPossible()
    }

    private func consumePendingFocusRequestIfPossible() {
        guard hasPendingFocusRequest, window != nil else {
            return
        }

        hasPendingFocusRequest = false
        focusIfPossible()
    }

    private func focusIfPossible() {
        window?.makeFirstResponder(self)
    }
}

@MainActor
final class TerminalViewDelegateProxy: @preconcurrency TerminalViewDelegate {
    private weak var terminalView: LocalProcessTerminalView?

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        terminalView?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        terminalView?.setTerminalTitle(source: source, title: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        terminalView?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        terminalView?.send(source: source, data: data)
    }

    func scrolled(source: TerminalView, position: Double) {
        terminalView?.scrolled(source: source, position: position)
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        // v1 denies terminal escape-sequence clipboard writes. User-initiated
        // SwiftTerm copy/paste and shell commands such as `pbcopy` remain available.
    }

    func clipboardRead(source: TerminalView) -> Data? {
        nil
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        // No custom iTerm2 OSC handling in v1.
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        terminalView?.rangeChanged(source: source, startY: startY, endY: endY)
    }
}
