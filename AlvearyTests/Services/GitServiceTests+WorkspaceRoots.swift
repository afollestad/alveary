import Foundation
import XCTest

@testable import Alveary

@MainActor
extension GitServiceTests {
    func testSubfolderGrantGitMutationsUseRepositoryRelativePaths() async throws {
        let fixture = try await WorkspaceRootGitFixture.make()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("sub").path
        let target = try await fixture.target(for: source)
        XCTAssertEqual(
            URL(fileURLWithPath: target.directory).resolvingSymlinksInPath().path,
            fixture.root.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(target.projectPath, source)
        XCTAssertEqual(target.workspaceTarget.sourceDirectory, source)
        let statuses = try await fixture.git.status(in: target.directory)
        XCTAssertEqual(Set(statuses.map(\.path)), ["sub/file.txt", "sub/sub/file.txt"])

        try await fixture.git.stage(paths: ["sub/file.txt"], in: target.directory)
        let staged = try await fixture.git.status(in: target.directory)
        XCTAssertEqual(staged.filter(\.isStaged).map(\.path), ["sub/file.txt"])
        XCTAssertEqual(staged.filter { !$0.isStaged }.map(\.path), ["sub/sub/file.txt"])

        try await fixture.git.unstage(paths: ["sub/file.txt"], in: target.directory)
        let unstaged = try await fixture.git.status(in: target.directory)
        XCTAssertTrue(unstaged.allSatisfy { !$0.isStaged })
        XCTAssertEqual(Set(unstaged.map(\.path)), ["sub/file.txt", "sub/sub/file.txt"])

        try await fixture.git.discard(paths: ["sub/file.txt"], scope: .all, in: target.directory)
        XCTAssertEqual(try fixture.contents("sub/file.txt"), "original\n")
        XCTAssertEqual(try fixture.contents("sub/sub/file.txt"), "changed\n")
        let remaining = try await fixture.git.status(in: target.directory)
        XCTAssertEqual(remaining.map(\.path), ["sub/sub/file.txt"])
    }

    func testOrdinaryFolderKeepsItsLiteralDiffTarget() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let git = CLIGitService(shell: DefaultShellRunner())
        let repositoryRoot = try await git.repositoryRoot(in: root.path)
        XCTAssertNil(repositoryRoot)
        let target = try await DiffViewerSwitchTarget(
            projectPath: root.path, worktreePath: nil, directory: root.path,
            baseRef: "main", remoteName: nil, conversationIds: []
        ).resolvingRepositoryDirectory(using: git)
        XCTAssertEqual(target.directory, root.path)
        XCTAssertEqual(target.projectPath, root.path)
        XCTAssertNoThrow(try target.workspaceTarget.requireSourceDirectory())
    }

    func testResolvedRepositoryDoesNotHideMissingGrantedSubfolder() async throws {
        let fixture = try await WorkspaceRootGitFixture.make()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("sub").path
        let target = try await fixture.target(for: source)
        try FileManager.default.removeItem(atPath: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.directory))
        XCTAssertThrowsError(try target.workspaceTarget.requireSourceDirectory())
        do {
            _ = try await fixture.target(for: source)
            XCTFail("Expected a missing source error instead of falling back to the repository")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains(source))
        }
    }
}

@MainActor
private struct WorkspaceRootGitFixture {
    let root: URL
    let shell: DefaultShellRunner
    let git: CLIGitService

    static func make() async throws -> WorkspaceRootGitFixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub/sub"), withIntermediateDirectories: true)
        let shell = DefaultShellRunner()
        let fixture = WorkspaceRootGitFixture(root: root, shell: shell, git: CLIGitService(shell: shell))
        do {
            try await fixture.run(["init", "-q", "-b", "main"])
            try fixture.writeFiles("original\n")
            try await fixture.run(["add", "-f", "--", "sub/file.txt", "sub/sub/file.txt"])
            try await fixture.run([
                "-c", "user.name=Workspace test", "-c", "user.email=workspace@example.invalid",
                "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "Seed files"
            ])
            try fixture.writeFiles("changed\n")
            return fixture
        } catch {
            fixture.remove()
            throw error
        }
    }

    func target(for source: String) async throws -> DiffViewerSwitchTarget {
        try await DiffViewerSwitchTarget(
            projectPath: source, worktreePath: nil, directory: source,
            baseRef: "main", remoteName: nil, conversationIds: []
        ).resolvingRepositoryDirectory(using: git)
    }

    func contents(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    private func writeFiles(_ contents: String) throws {
        for path in ["sub/file.txt", "sub/sub/file.txt"] {
            try Data(contents.utf8).write(to: root.appendingPathComponent(path))
        }
    }

    private func run(_ arguments: [String]) async throws {
        let result = try await shell.run(executable: "/usr/bin/git", args: arguments, in: root.path)
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
    }
}
