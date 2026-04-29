import XCTest
import SwiftUI

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

    // Covers the overflow state: enough tab chips at a narrow pane width that the
    // row must scroll. Captures the trailing-edge divider at initial scroll (tabs
    // visible past the right edge) and that the fixed terminal icon + close button
    // sit 8pt from the respective dividers / scrolling tabs.
    func testTerminalPaneSessionsOverflow() {
        let terminalManager = TerminalManager()
        for index in 1...8 {
            terminalManager.createSession(
                title: "Task \(index)",
                projectName: "Alveary",
                threadName: "Thread \(index)",
                currentDirectory: "/Users/alice/Development/alveary",
                command: "./scripts/task\(index).sh",
                output: "",
                status: .running,
                select: index == 1
            )
        }

        assertMacSnapshot(
            TerminalPane(onClose: {})
                .environment(terminalManager),
            size: CGSize(width: 600, height: 240),
            named: "terminal_pane_sessions_overflow"
        )
    }
}
