@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testTerminalToolbarButtonStates() {
        assertMacSnapshot(
            HStack(spacing: 10) {
                TerminalToolbarButton(title: "Terminal", displayState: .idle, action: {})
                    .primaryToolbarIconButtonStyle()
                TerminalToolbarButton(title: "Terminal", displayState: .running, action: {})
                    .primaryToolbarIconButtonStyle()
                TerminalToolbarButton(title: "Terminal", displayState: .completed(.succeeded), action: {})
                    .primaryToolbarIconButtonStyle()
                TerminalToolbarButton(title: "Terminal", displayState: .completed(.failed), action: {})
                    .primaryToolbarIconButtonStyle()
                TerminalToolbarButton(title: "Terminal", displayState: .completed(.cancelled), action: {})
                    .primaryToolbarIconButtonStyle()
            }
            .padding(12),
            size: CGSize(width: 640, height: 64),
            named: "terminal_toolbar_button_states"
        )
    }

    func testTerminalPaneSessions() {
        let terminalManager = makeSnapshotTerminalManager([
            SnapshotTerminalSession(
                title: "Build",
                projectName: "Alveary",
                threadName: "Refine Terminal Drawer Layout",
                currentDirectory: "/Users/alice/Development/alveary",
                command: "./scripts/build.sh",
                viewportText: "$ ./scripts/build.sh\nBuild started...\nCompiling TerminalPane.swift\nBuild Succeeded",
                status: .succeeded,
                select: false
            ),
            SnapshotTerminalSession(
                title: "Seed DB",
                projectName: "Sandbox",
                threadName: "Seed Review",
                currentDirectory: "/Users/alice/Development/sandbox",
                command: "bin/seed-db",
                viewportText: "$ bin/seed-db\nSeeding records...",
                status: .running,
                select: false
            ),
            SnapshotTerminalSession(
                title: "Test",
                projectName: "Website",
                threadName: "Sidebar Cache Preservation Fix",
                currentDirectory: "/Users/alice/Development/website",
                command: "npm test",
                viewportText: "$ npm test\n1 failing test\n- should preserve cached sidebar state",
                status: .failed
            )
        ])

        assertMacSnapshot(
            TerminalPane(onClose: {})
                .environment(terminalManager),
            size: CGSize(width: 1200, height: 420),
            named: "terminal_pane_sessions"
        )
    }

    func testTerminalPaneSessionChipInlineCode() {
        let terminalManager = makeSnapshotTerminalManager([
            SnapshotTerminalSession(
                title: "Open",
                projectName: "Alveary",
                threadName: "Really long `code block` stuff",
                currentDirectory: "/Users/alice/Development/alveary",
                command: "open .",
                viewportText: "$ open .",
                status: .running,
                select: false
            ),
            SnapshotTerminalSession(
                title: "Open",
                projectName: "Alveary",
                threadName: "Test `code` Rendering",
                currentDirectory: "/Users/alice/Development/alveary",
                command: "open .",
                viewportText: "$ open .\n.",
                status: .running
            )
        ])

        assertMacSnapshot(
            TerminalPane(onClose: {})
                .environment(terminalManager),
            size: CGSize(width: 1200, height: 260),
            named: "terminal_pane_session_chip_inline_code"
        )
    }

    // Covers the overflow state: enough tab chips at a narrow pane width that the
    // row must scroll. Captures the trailing-edge divider at initial scroll (tabs
    // visible past the right edge) and that the fixed terminal icon + close button
    // sit 8pt from the respective dividers / scrolling tabs.
    func testTerminalPaneSessionsOverflow() {
        let terminalManager = makeSnapshotTerminalManager((1...8).map { index in
            SnapshotTerminalSession(
                title: "Task \(index)",
                projectName: "Alveary",
                threadName: "Thread \(index)",
                currentDirectory: "/Users/alice/Development/alveary",
                command: "./scripts/task\(index).sh",
                viewportText: "$ ./scripts/task\(index).sh",
                status: .running,
                select: index == 1
            )
        })

        assertMacSnapshot(
            TerminalPane(onClose: {})
                .environment(terminalManager),
            size: CGSize(width: 600, height: 260),
            named: "terminal_pane_sessions_overflow"
        )
    }

    func testTerminalPaneEmptyState() {
        let terminalManager = TerminalManager(controllerFactory: SnapshotTerminalControllerFactory())

        assertMacSnapshot(
            TerminalPane(onClose: {})
                .environment(terminalManager),
            size: CGSize(width: 900, height: 260),
            named: "terminal_pane_empty_state"
        )
    }

    func testTerminalPaneShellExited() {
        let terminalManager = makeSnapshotTerminalManager([
            SnapshotTerminalSession(
                kind: .shell,
                title: "Shell",
                projectName: "Alveary",
                threadName: "Investigation",
                currentDirectory: "/Users/alice/Development/alveary",
                viewportText: "$ exit 1\nlogout",
                status: .failed
            )
        ])

        assertMacSnapshot(
            TerminalPane(onClose: {})
                .environment(terminalManager),
            size: CGSize(width: 900, height: 260),
            named: "terminal_pane_shell_exited"
        )
    }

    func testTerminalPaneDarkViewportColors() {
        let terminalManager = makeSnapshotTerminalManager([
            SnapshotTerminalSession(
                kind: .shell,
                title: "Shell",
                projectName: "Alveary",
                currentDirectory: "/Users/alice/Development/alveary",
                viewportText: "$ printf 'dark mode'\ndark mode",
                status: .running
            )
        ])

        assertMacSnapshot(
            TerminalPane(onClose: {})
                .environment(terminalManager),
            size: CGSize(width: 900, height: 260),
            named: "terminal_pane_dark_viewport_colors",
            colorScheme: .dark
        )
    }
}

@MainActor
private func makeSnapshotTerminalManager(_ sessions: [SnapshotTerminalSession]) -> TerminalManager {
    let factory = SnapshotTerminalControllerFactory()
    let manager = TerminalManager(controllerFactory: factory)

    for session in sessions {
        factory.queuedViewportTexts.append(session.viewportText)
        manager.createSession(
            kind: session.kind,
            title: session.title,
            projectName: session.projectName,
            threadName: session.threadName,
            currentDirectory: session.currentDirectory,
            command: session.command,
            status: session.status,
            select: session.select,
            launchConfiguration: TerminalLaunchConfiguration(
                executable: "/bin/zsh",
                args: [],
                environment: ["TERM=xterm-256color"],
                execName: "-zsh",
                currentDirectory: session.currentDirectory ?? "/Users/alice"
            )
        )
    }

    return manager
}

private struct SnapshotTerminalSession {
    var kind: TerminalSession.Kind = .projectAction
    var title: String
    var projectName: String?
    var threadName: String?
    var currentDirectory: String?
    var command: String?
    var viewportText: String
    var status: TerminalSession.Status
    var select = true
}

@MainActor
private final class SnapshotTerminalControllerFactory: TerminalSessionControllerFactory {
    var queuedViewportTexts: [String] = []

    func makeController(
        sessionID: UUID,
        configuration: TerminalLaunchConfiguration,
        delegate: any TerminalSessionControllerDelegate
    ) -> any TerminalSessionControlling {
        let text = queuedViewportTexts.isEmpty ? "$ " : queuedViewportTexts.removeFirst()
        return SnapshotTerminalController(viewportText: text)
    }
}

@MainActor
private final class SnapshotTerminalController: TerminalSessionControlling {
    let terminalView: SnapshotTerminalFakeView

    var view: NSView {
        terminalView
    }

    init(viewportText: String) {
        terminalView = SnapshotTerminalFakeView(text: viewportText)
    }

    func start() {}
    func terminate() {}
    func requestFocus() {}

    func reapplyTheme() {
        terminalView.applyPalette()
    }
}

private final class SnapshotTerminalFakeView: NSView {
    private let text: String
    private var backgroundColor = NSColor.black
    private var foregroundColor = NSColor.white

    override var isFlipped: Bool {
        true
    }

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func applyPalette() {
        let palette = TerminalThemePalette.resolved(for: effectiveAppearance)
        backgroundColor = palette.background
        foregroundColor = palette.foreground
        layer?.backgroundColor = backgroundColor.cgColor
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPalette()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle
        ]
        (text as NSString).draw(
            in: bounds.insetBy(dx: 14, dy: 12),
            withAttributes: attributes
        )
    }
}
