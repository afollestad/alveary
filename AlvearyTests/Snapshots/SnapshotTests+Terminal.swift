import XCTest

@testable import Alveary

extension SnapshotTests {
    func testTerminalPaneSessions() {
        let terminalManager = TerminalManager()
        terminalManager.createSession(
            title: "Build",
            projectName: "Alveary",
            threadName: "Refine Terminal Drawer",
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
            threadName: "Sidebar Cache Fix",
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
}
