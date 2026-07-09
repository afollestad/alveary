import XCTest

@testable import Alveary

final class TerminalLaunchBuilderTests: XCTestCase {
    func testResolvedShellPrefersExecutableZshFromEnvironment() {
        let builder = makeBuilder(
            environment: ["SHELL": "/usr/local/bin/zsh"],
            passwdShell: "/bin/bash",
            executablePaths: ["/usr/local/bin/zsh", "/bin/bash"]
        )

        XCTAssertEqual(builder.resolvedShellPath(), "/usr/local/bin/zsh")
    }

    func testResolvedShellPrefersExecutableZshFromPasswdBeforeBinZsh() {
        let builder = makeBuilder(
            environment: ["SHELL": "/bin/bash"],
            passwdShell: "/opt/homebrew/bin/zsh",
            executablePaths: ["/bin/bash", "/bin/zsh", "/opt/homebrew/bin/zsh"]
        )

        XCTAssertEqual(builder.resolvedShellPath(), "/opt/homebrew/bin/zsh")
    }

    func testResolvedShellFallsBackToBinZshBeforeExecutableNonZshShell() {
        let builder = makeBuilder(
            environment: ["SHELL": "/usr/local/bin/fish"],
            passwdShell: nil,
            executablePaths: ["/usr/local/bin/fish", "/bin/zsh"]
        )

        XCTAssertEqual(builder.resolvedShellPath(), "/bin/zsh")
    }

    func testResolvedShellUsesExecutableEnvironmentShellWhenZshIsUnavailable() {
        let builder = makeBuilder(
            environment: ["SHELL": "/usr/local/bin/fish"],
            passwdShell: nil,
            executablePaths: ["/usr/local/bin/fish"]
        )

        XCTAssertEqual(builder.resolvedShellPath(), "/usr/local/bin/fish")
    }

    func testResolvedShellFallsBackToBinBash() {
        let builder = makeBuilder(
            environment: ["SHELL": "/missing/zsh"],
            passwdShell: nil,
            executablePaths: []
        )

        XCTAssertEqual(builder.resolvedShellPath(), "/bin/bash")
    }

    func testShellConfigurationUsesLoginExecNameAndSerializedEnvironment() {
        let builder = makeBuilder(
            environment: [
                "PATH": "/usr/bin",
                "SHELL": "/bin/zsh"
            ],
            executablePaths: ["/bin/zsh"]
        )

        let configuration = builder.shell(currentDirectory: "/Users/alice/Project")
        let environment = environmentDictionary(configuration.environment)

        XCTAssertEqual(configuration.executable, "/bin/zsh")
        XCTAssertEqual(configuration.args, [])
        XCTAssertEqual(configuration.execName, "-zsh")
        XCTAssertEqual(configuration.currentDirectory, "/Users/alice/Project")
        XCTAssertEqual(environment["HOME"], "/Users/alice")
        XCTAssertEqual(environment["USER"], "alice")
        XCTAssertEqual(environment["SHELL"], "/bin/zsh")
        XCTAssertEqual(environment["PWD"], "/Users/alice/Project")
        XCTAssertEqual(environment["TERM"], "xterm-256color")
        XCTAssertEqual(environment["COLORTERM"], "truecolor")
        XCTAssertEqual(environment["TERM_PROGRAM"], "Alveary")
        XCTAssertEqual(environment["LANG"], "en_US.UTF-8")
        XCTAssertEqual(environment["LC_CTYPE"], "en_US.UTF-8")
        XCTAssertTrue(environment["PATH"]?.hasPrefix("/usr/bin") == true)
        XCTAssertTrue(environment["PATH"]?.contains("/opt/homebrew/bin") == true)
        XCTAssertTrue(environment["PATH"]?.contains("/usr/local/bin") == true)
    }

    func testProjectActionConfigurationUsesInteractiveCommandArgs() {
        let builder = makeBuilder(
            environment: ["SHELL": "/bin/zsh"],
            executablePaths: ["/bin/zsh"]
        )

        let configuration = builder.projectAction(
            command: "./scripts/build.sh",
            currentDirectory: "/Users/alice/Project"
        )

        XCTAssertEqual(configuration.executable, "/bin/zsh")
        XCTAssertEqual(configuration.args, ["-i", "-c", "./scripts/build.sh"])
        XCTAssertEqual(configuration.execName, "-zsh")
        XCTAssertEqual(configuration.currentDirectory, "/Users/alice/Project")
    }

    func testDefaultShellDirectoryFallbackOrder() {
        let builder = makeBuilder()

        XCTAssertEqual(
            builder.defaultShellDirectory(
                threadWorktreePath: " /worktree ",
                threadProjectPath: "/project",
                selectedProjectPath: "/selected"
            ),
            "/worktree"
        )
        XCTAssertEqual(
            builder.defaultShellDirectory(
                threadWorktreePath: "",
                threadProjectPath: "/project",
                selectedProjectPath: "/selected"
            ),
            "/project"
        )
        XCTAssertEqual(
            builder.defaultShellDirectory(
                threadWorktreePath: nil,
                threadProjectPath: " ",
                selectedProjectPath: "/selected"
            ),
            "/selected"
        )
        XCTAssertEqual(
            builder.defaultShellDirectory(
                threadWorktreePath: nil,
                threadProjectPath: nil,
                selectedProjectPath: nil
            ),
            "/Users/alice"
        )
    }

    private func makeBuilder(
        environment: [String: String] = [:],
        passwdShell: String? = nil,
        executablePaths: Set<String> = []
    ) -> TerminalLaunchBuilder {
        var builder = TerminalLaunchBuilder()
        builder.environment = {
            environment
        }
        builder.homeDirectory = {
            "/Users/alice"
        }
        builder.userName = {
            "alice"
        }
        builder.passwdShell = {
            passwdShell
        }
        builder.isExecutable = { path in
            executablePaths.contains(path)
        }
        return builder
    }

    private func environmentDictionary(_ entries: [String]) -> [String: String] {
        entries.reduce(into: [:]) { result, entry in
            let pieces = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else {
                return
            }

            result[String(pieces[0])] = String(pieces[1])
        }
    }
}
