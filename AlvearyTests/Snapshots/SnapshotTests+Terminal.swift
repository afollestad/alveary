import XCTest

@testable import Alveary

extension SnapshotTests {
    func testTerminalPaneSessions() {
        let terminalManager = TerminalManager()
        terminalManager.createSession(
            title: "Build",
            projectName: "Alveary",
            threadName: "Refine Terminal Drawer Layout",
            currentDirectory: "/Users/alice/Development/alveary",
            command: "./scripts/build.sh",
            output: "Build started...\nCompiling TerminalPane.swift\nBuild Succeeded",
            status: .succeeded,
            select: false
        )
        terminalManager.createSession(
            title: "Seed DB",
            projectName: "Sandbox",
            threadName: "Seed Review",
            currentDirectory: "/Users/alice/Development/sandbox",
            command: "bin/seed-db",
            output: "Seeding records...",
            status: .running,
            select: false
        )
        terminalManager.createSession(
            title: "Test",
            projectName: "Website",
            threadName: "Sidebar Cache Preservation Fix",
            currentDirectory: "/Users/alice/Development/website",
            command: "npm test",
            output: "1 failing test\n- should preserve cached sidebar state",
            status: .failed
        )

        assertMacSnapshot(
            TerminalPane(onClose: {})
                .environment(terminalManager),
            size: CGSize(width: 1200, height: 420),
            named: "terminal_pane_sessions"
        )
    }

    func testTerminalPaneSessionChipInlineCode() {
        let terminalManager = TerminalManager()
        // Unselected chip: label is truncated inside the code span, so the inline-code
        // chip renders over the muted (unselected) capsule fill.
        terminalManager.createSession(
            title: "Open",
            projectName: "Alveary",
            threadName: "Really long `code block` stuff",
            currentDirectory: "/Users/alice/Development/alveary",
            command: "open .",
            output: "",
            status: .running,
            select: false
        )
        // Selected chip: label fits without truncation, so the inline-code chip renders
        // in the on-accent style against the selected capsule fill.
        terminalManager.createSession(
            title: "Open",
            projectName: "Alveary",
            threadName: "Test `code` Rendering",
            currentDirectory: "/Users/alice/Development/alveary",
            command: "open .",
            output: "",
            status: .running
        )

        assertMacSnapshot(
            TerminalPane(onClose: {})
                .environment(terminalManager),
            size: CGSize(width: 1200, height: 240),
            named: "terminal_pane_session_chip_inline_code"
        )
    }
}
