import Foundation
import XCTest

@testable import Alveary

final class TerminalActionShellIntegrationTests: XCTestCase {
    func testPrepareWritesPrivateZshStartupFilesAndOverlaysEnvironment() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let configuration = TerminalLaunchConfiguration(
            executable: "/bin/zsh",
            args: [],
            environment: [
                "ALVEARY_ZSH_USER_ZDOTDIR=/stale",
                "HOME=/Users/alice",
                "TERM=xterm-256color",
                "ZDOTDIR=/Users/alice/.config/zsh"
            ],
            execName: "-zsh",
            currentDirectory: "/Users/alice/Project",
            projectActionCommand: "SECRET_ACTION_COMMAND"
        )

        let integration = try XCTUnwrap(
            TerminalProjectActionShellIntegration.prepare(
                configuration: configuration,
                sessionID: UUID(),
                temporaryDirectory: temporaryDirectory
            )
        )
        defer { integration.cleanup() }

        XCTAssertTrue(integration.environment.contains("ZDOTDIR=\(integration.directoryURL.path)"))
        XCTAssertTrue(integration.environment.contains("ALVEARY_ZSH_USER_ZDOTDIR=/Users/alice/.config/zsh"))
        XCTAssertEqual(integration.environment.filter { $0.hasPrefix("ZDOTDIR=") }.count, 1)
        XCTAssertEqual(integration.environment.filter { $0.hasPrefix("ALVEARY_ZSH_USER_ZDOTDIR=") }.count, 1)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: integration.directoryURL.path)
        let directoryPermissions = try XCTUnwrap(directoryAttributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(directoryPermissions & 0o777, 0o700)

        for fileName in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
            let fileURL = integration.directoryURL.appendingPathComponent(fileName)
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue

            XCTAssertEqual(permissions & 0o777, 0o600)
            XCTAssertFalse(contents.contains("SECRET_ACTION_COMMAND"))
            try assertValidZshSyntax(fileURL)
        }

        let zlogin = try String(
            contentsOf: integration.directoryURL.appendingPathComponent(".zlogin"),
            encoding: .utf8
        )
        XCTAssertTrue(zlogin.contains("source \"$ZDOTDIR/.zlogin\""))
        XCTAssertTrue(zlogin.contains("zle -N zle-line-init"))
        XCTAssertTrue(zlogin.contains("precmd_functions=("))
        XCTAssertTrue(zlogin.contains("AlvearyProjectAction=\(integration.markerToken):ready"))
        XCTAssertTrue(zlogin.contains("AlvearyProjectAction=\(integration.markerToken):complete:%d"))
    }

    func testPrepareReturnsNilForUnsupportedShell() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let configuration = TerminalLaunchConfiguration(
            executable: "/bin/bash",
            args: [],
            environment: ["HOME=/Users/alice"],
            execName: "-bash",
            currentDirectory: "/Users/alice/Project",
            projectActionCommand: "make test"
        )

        let integration = try TerminalProjectActionShellIntegration.prepare(
            configuration: configuration,
            sessionID: UUID(),
            temporaryDirectory: temporaryDirectory
        )

        XCTAssertNil(integration)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path).isEmpty)
    }

    func testCleanupRemovesIntegrationDirectory() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let integration = try XCTUnwrap(
            TerminalProjectActionShellIntegration.prepare(
                configuration: sampleConfiguration,
                sessionID: UUID(),
                temporaryDirectory: temporaryDirectory
            )
        )

        integration.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: integration.directoryURL.path))
    }

    func testMarkerParserAcceptsExpectedTokenOnly() {
        let token = "expected-token"

        XCTAssertEqual(
            TerminalProjectActionMarker.parse(
                content: Array("AlvearyProjectAction=\(token):ready".utf8)[...],
                expectedToken: token
            ),
            .ready
        )
        XCTAssertEqual(
            TerminalProjectActionMarker.parse(
                content: Array("AlvearyProjectAction=\(token):complete:7".utf8)[...],
                expectedToken: token
            ),
            .completed(exitCode: 7)
        )
        XCTAssertNil(
            TerminalProjectActionMarker.parse(
                content: Array("AlvearyProjectAction=other-token:complete:0".utf8)[...],
                expectedToken: token
            )
        )
        XCTAssertNil(
            TerminalProjectActionMarker.parse(
                content: Array("AlvearyProjectAction=\(token):complete:nope".utf8)[...],
                expectedToken: token
            )
        )
    }

    func testCommandEncoderUsesBracketedPasteAndNormalizesNewlines() {
        let bytes = TerminalProjectActionCommandEncoder.bytes(
            command: "printf one\r\nprintf two\rprintf three",
            bracketedPasteEnabled: true
        )
        let expected = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
            + Array("printf one\nprintf two\nprintf three".utf8)
            + [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E, 0x0D]

        XCTAssertEqual(bytes, expected)
    }

    func testCommandEncoderFallsBackToRawInputWithoutBracketedPaste() {
        let bytes = TerminalProjectActionCommandEncoder.bytes(
            command: "echo ready",
            bracketedPasteEnabled: false
        )

        XCTAssertEqual(bytes, Array("echo ready".utf8) + [0x0D])
    }

    func testZshIntegrationInjectsAtRealPromptReportsCompletionAndKeepsShellOpen() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/expect"))
        let fixture = try makeInteractiveZshFixture()
        defer { fixture.cleanup() }

        let result = try runExpectScript(makeExpectScript(for: fixture), in: fixture.temporaryDirectory)

        XCTAssertEqual(result.status, 0, result.output)
    }
}

private extension TerminalActionShellIntegrationTests {
    func makeExpectScript(for fixture: InteractiveZshFixture) -> String {
        expectStartupScript(for: fixture) + expectActionScript(for: fixture)
    }

    func expectStartupScript(for fixture: InteractiveZshFixture) -> String {
        #"""
        log_user 1
        set timeout 10
        set env(HOME) {\#(fixture.temporaryDirectory.path)}
        set env(TERM) {xterm-256color}
        set env(ZDOTDIR) {\#(fixture.integration.directoryURL.path)}
        set env(ALVEARY_ZSH_USER_ZDOTDIR) {\#(fixture.userZDOTDIR.path)}
        spawn -noecho /bin/zsh -l
        set saw_prompt 0
        set saw_ready 0
        set saw_user_line_init 0
        while {!$saw_prompt || !$saw_ready || !$saw_user_line_init} {
          expect {
            -exact {REAL_PROMPT> } { set saw_prompt 1 }
            -exact "\033]1337;UserLineInit=seen\007" { set saw_user_line_init 1 }
            -exact "\033]1337;AlvearyProjectAction=\#(fixture.integration.markerToken):ready\007" { set saw_ready 1 }
            timeout { exit 21 }
            eof { exit 22 }
          }
        }
        send -- "printf 'ACTION_OUTPUT\\n'\r"

        """#
    }

    func expectActionScript(for fixture: InteractiveZshFixture) -> String {
        #"""
        expect {
          -exact {printf 'ACTION_OUTPUT\n'} {}
          timeout { exit 23 }
          eof { exit 24 }
        }
        expect {
          -exact {ACTION_OUTPUT} {}
          timeout { exit 25 }
          eof { exit 26 }
        }
        expect {
          -exact "\033]1337;AlvearyProjectAction=\#(fixture.integration.markerToken):complete:0\007" {}
          timeout { exit 27 }
          eof { exit 28 }
        }
        expect {
          -exact {REAL_PROMPT> } {}
          timeout { exit 29 }
          eof { exit 30 }
        }
        expect {
          -exact "\033]1337;UserLineInit=seen\007" {}
          timeout { exit 31 }
          eof { exit 32 }
        }
        send -- "printf 'AFTER_ACTION\\n'\r"
        expect {
          -exact {AFTER_ACTION} {}
          timeout { exit 33 }
          eof { exit 34 }
        }
        send -- "exit\r"
        expect eof
        """#
    }

    func makeInteractiveZshFixture() throws -> InteractiveZshFixture {
        let temporaryDirectory = try makeTemporaryDirectory()
        do {
            let userZDOTDIR = temporaryDirectory.appendingPathComponent("user-zdotdir", isDirectory: true)
            try FileManager.default.createDirectory(at: userZDOTDIR, withIntermediateDirectories: false)
            try writeInteractiveUserStartupFiles(to: userZDOTDIR)
            let configuration = TerminalLaunchConfiguration(
                executable: "/bin/zsh",
                args: [],
                environment: [
                    "HOME=\(temporaryDirectory.path)",
                    "TERM=xterm-256color",
                    "ZDOTDIR=\(userZDOTDIR.path)"
                ],
                execName: "-zsh",
                currentDirectory: temporaryDirectory.path,
                projectActionCommand: "printf 'ACTION_OUTPUT\\n'"
            )
            let integration = try XCTUnwrap(
                TerminalProjectActionShellIntegration.prepare(
                    configuration: configuration,
                    sessionID: UUID(),
                    temporaryDirectory: temporaryDirectory
                )
            )
            return InteractiveZshFixture(
                temporaryDirectory: temporaryDirectory,
                userZDOTDIR: userZDOTDIR,
                integration: integration
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    func writeInteractiveUserStartupFiles(to userZDOTDIR: URL) throws {
        try "PROMPT='REAL_PROMPT> '\n".write(
            to: userZDOTDIR.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )
        let zlogin = #"""
        function user_line_init {
          printf '\033]1337;UserLineInit=seen\007'
        }
        zle -N zle-line-init user_line_init

        """#
        try zlogin.write(
            to: userZDOTDIR.appendingPathComponent(".zlogin"),
            atomically: true,
            encoding: .utf8
        )
    }

    func runExpectScript(_ contents: String, in temporaryDirectory: URL) throws -> (status: Int32, output: String) {
        let scriptURL = temporaryDirectory.appendingPathComponent("integration.exp")
        try contents.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
        process.arguments = [scriptURL.path]
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        let output = String(
            data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errorOutput = String(
            data: standardError.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (process.terminationStatus, output + errorOutput)
    }

    var sampleConfiguration: TerminalLaunchConfiguration {
        TerminalLaunchConfiguration(
            executable: "/bin/zsh",
            args: [],
            environment: ["HOME=/Users/alice", "TERM=xterm-256color"],
            execName: "-zsh",
            currentDirectory: "/Users/alice/Project",
            projectActionCommand: "make test"
        )
    }

    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalActionShellIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func assertValidZshSyntax(_ fileURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n", fileURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "Invalid zsh syntax in \(fileURL.lastPathComponent)")
    }
}

private struct InteractiveZshFixture {
    let temporaryDirectory: URL
    let userZDOTDIR: URL
    let integration: TerminalProjectActionShellIntegration

    func cleanup() {
        integration.cleanup()
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}
