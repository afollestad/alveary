import Foundation
import SwiftData
import XCTest

@testable import Alveary

private actor DirectoryCreatingShellRunner: ShellRunner {
    private let path: String

    init(path: String) {
        self.path = path
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return ShellResult(
            stdout: "",
            stderr: "fatal: repository 'missing' not found",
            exitCode: 128,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
    }
}

@MainActor
extension SidebarViewModelTests {
    func testCloneRepositoryInvokesGitCloneAndPersistsProject() async throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.0.0", gitHubAuthenticated: false)
        let parent = try makeParentDirectory()
        let destination = parent.appendingPathComponent("repo").path

        // 1. git clone (succeeds, mock does not create the directory).
        await fixture.shell.enqueue(.success(shellResult(stdout: "")))
        // 2..N. createProject → resolveProjectDetails git probes.
        await fixture.shell.enqueue(.success(shellResult(stdout: "\(destination)\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "main\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "\n")))

        let project = try await fixture.viewModel.cloneRepository(
            url: "https://github.com/owner/repo.git",
            into: destination,
            branch: nil
        )

        XCTAssertEqual(project.path, destination)
        XCTAssertEqual(project.name, "repo")
        XCTAssertEqual(project.sidebarSortOrder, 0)
        XCTAssertNil(project.pinnedSortOrder)

        let invocations = await fixture.shell.invocations
        XCTAssertEqual(invocations.first?.args, ["clone", "https://github.com/owner/repo.git", destination])
    }

    func testCloneRepositoryWithBranchPassesSingleBranchArgs() async throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.0.0", gitHubAuthenticated: false)
        let parent = try makeParentDirectory()
        let destination = parent.appendingPathComponent("repo").path

        await fixture.shell.enqueue(.success(shellResult(stdout: "")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "\(destination)\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "dev\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "\n")))
        await fixture.shell.enqueue(.success(shellResult(stdout: "\n")))

        _ = try await fixture.viewModel.cloneRepository(
            url: "git@github.com:owner/repo.git",
            into: destination,
            branch: "dev"
        )

        let invocations = await fixture.shell.invocations
        XCTAssertEqual(
            invocations.first?.args,
            ["clone", "git@github.com:owner/repo.git", destination, "--branch", "dev", "--single-branch"]
        )
    }

    func testCloneRepositorySurfacesGitStderrAndLeavesNoDestination() async throws {
        let fixture = try SidebarTestFixture()
        let parent = try makeParentDirectory()
        let destination = parent.appendingPathComponent("repo").path

        await fixture.shell.enqueue(.success(
            shellResult(
                stdout: "",
                stderr: "fatal: repository 'bad' not found\n",
                exitCode: 128
            )
        ))

        do {
            _ = try await fixture.viewModel.cloneRepository(
                url: "https://example.com/missing.git",
                into: destination,
                branch: nil
            )
            XCTFail("Expected clone to throw")
        } catch let error as GitError {
            XCTAssertEqual(error, .commandFailed("fatal: repository 'bad' not found"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination))
    }

    func testCloneRepositoryRejectsExistingDestinationWithoutInvokingGit() async throws {
        let fixture = try SidebarTestFixture()
        let parent = try makeParentDirectory()
        let destination = parent.appendingPathComponent("repo").path
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: false)

        do {
            _ = try await fixture.viewModel.cloneRepository(
                url: "https://github.com/owner/repo.git",
                into: destination,
                branch: nil
            )
            XCTFail("Expected clone to throw")
        } catch let error as GitError {
            guard case .commandFailed(let message) = error else {
                XCTFail("Unexpected GitError: \(error)")
                return
            }
            XCTAssertTrue(message.contains("Destination already exists"))
        }

        let invocations = await fixture.shell.invocations
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination))
    }

    func testCloneRepositoryRemovesArtifactsCreatedByShell() async throws {
        let parent = try makeParentDirectory()
        let destination = parent.appendingPathComponent("repo").path

        // Simulate git clone creating the directory before returning a non-zero exit.
        let shell = DirectoryCreatingShellRunner(path: destination)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: configuration
        )
        let viewModel = SidebarViewModel(
            agentsManager: SidebarMockAgentsManager(),
            modelContext: ModelContext(container),
            shell: shell,
            gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
            worktreeManager: SidebarMockWorktreeManager(),
            settingsService: InMemorySettingsService(current: AppSettings()),
            notificationManager: RecordingNotificationManager()
        )

        do {
            _ = try await viewModel.cloneRepository(
                url: "https://example.com/missing.git",
                into: destination,
                branch: nil
            )
            XCTFail("Expected clone to throw")
        } catch is GitError {
            // expected
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination))
    }

    func testCloneRepositoryCleansUpIntermediateDirectoriesItCreated() async throws {
        let fixture = try SidebarTestFixture()
        let parent = try makeParentDirectory()
        let intermediate = parent.appendingPathComponent("nested/dir", isDirectory: true)
        let destination = intermediate.appendingPathComponent("repo").path

        await fixture.shell.enqueue(.success(
            shellResult(
                stdout: "",
                stderr: "fatal: repository not found\n",
                exitCode: 128
            )
        ))

        do {
            _ = try await fixture.viewModel.cloneRepository(
                url: "https://example.com/missing.git",
                into: destination,
                branch: nil
            )
            XCTFail("Expected clone to throw")
        } catch is GitError {
            // expected
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: intermediate.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: intermediate.deletingLastPathComponent().path)
        )
        // The pre-existing parent the user picked must remain untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: parent.path))
    }

    func testCloneRepositoryDoesNotRemoveSiblingArtifactsInPreExistingParent() async throws {
        let fixture = try SidebarTestFixture()
        let parent = try makeParentDirectory()
        let sibling = parent.appendingPathComponent("other-project")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let destination = parent.appendingPathComponent("repo").path

        await fixture.shell.enqueue(.success(
            shellResult(
                stdout: "",
                stderr: "fatal: repository not found\n",
                exitCode: 128
            )
        ))

        do {
            _ = try await fixture.viewModel.cloneRepository(
                url: "https://example.com/missing.git",
                into: destination,
                branch: nil
            )
            XCTFail("Expected clone to throw")
        } catch is GitError {
            // expected
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: parent.path))
    }

    func testCloneRepositoryRejectsEmptyURL() async throws {
        let fixture = try SidebarTestFixture()
        let parent = try makeParentDirectory()
        let destination = parent.appendingPathComponent("repo").path

        do {
            _ = try await fixture.viewModel.cloneRepository(
                url: "   ",
                into: destination,
                branch: nil
            )
            XCTFail("Expected clone to throw")
        } catch let error as GitError {
            XCTAssertEqual(error, .commandFailed("Repository URL is required."))
        }

        let invocations = await fixture.shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    private func makeParentDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-clone-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func shellResult(
        stdout: String,
        stderr: String = "",
        exitCode: Int32 = 0
    ) -> ShellResult {
        ShellResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
    }
}
