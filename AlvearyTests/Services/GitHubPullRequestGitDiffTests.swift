import AgentCLIKit
import Foundation
import Testing

@testable import Alveary

struct GitHubPullRequestGitDiffTests {
    @Test(arguments: [false, true])
    func `large diff capture failures recover from Git objects`(truncated: Bool) async throws {
        let fixture = try await GitDiffRepositoryFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let runner = GitDiffRepositoryRunner(fixture: fixture, truncated: truncated)
        let service = GitHubPullRequestsService(shellRunner: runner, executableResolver: DiffTestExecutableResolver())
        let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        async let first = service.fetchDiffSnapshot(identifier)
        async let second = service.fetchDiffSnapshot(identifier)
        let (snapshot, reused) = try await (first, second)
        #expect(snapshot.id == reused.id)
        #expect(snapshot.byteCount > 5 * 1024 * 1024)
        #expect(throws: PullRequestsServiceError.responseTooLarge) { try snapshot.text(maxBytes: 5 * 1024 * 1024) }
        #expect(await runner.rawDiffCalls == 1)
        #expect(snapshot.files.map(\.metadata.path).sorted() == ["binary", "deleted", "large", "ordinary", "renamed\né\t.txt"].sorted())
        let parsed = try snapshot.parsedFiles(paths: ["ordinary"])
        #expect(parsed.first?.hunks.first?.lines.map(\.content) == ["before", "after"])
        #expect(snapshot.files.first { $0.metadata.path == "renamed\né\t.txt" }?.metadata.oldPath == "old.txt")
        #expect(snapshot.files.first { $0.metadata.path == "binary" }?.metadata.isBinary == true)
        #expect(try await fixture.run(["rev-parse", "HEAD"]) == fixture.comparison.base)
        #expect(try await fixture.run(["status", "--porcelain"]).isEmpty)
        let invocations = await runner.gitArguments
        #expect(invocations.contains { $0.contains("--filter=blob:none") && $0.contains("refs/pull/7/head:refs/heads/pull-request") })
        #expect(invocations.contains { $0.contains("--no-ext-diff") && $0.contains("--no-textconv") })
        try await verifyProposal(using: service)
    }

    @Test func `unrelated errors do not download a repository`() async throws {
        let shell = MockShellRunner()
        await shell.setResponder { invocation in
            if invocation.args.first == "api" {
                let base = String(repeating: "a", count: 40)
                let head = String(repeating: "b", count: 40)
                return .success(pullRequestsShellResult(stdout: "{\"base\":\"\(base)\",\"head\":\"\(head)\"}"))
            }
            return .success(pullRequestsShellResult(stderr: "gh: Bad credentials (HTTP 401)", exitCode: 1))
        }
        let service = GitHubPullRequestsService(shellRunner: shell, executableResolver: DiffTestExecutableResolver())
        await #expect(throws: PullRequestsServiceError.notAuthenticated) {
            try await service.fetchDiffSnapshot(.init(owner: "octo", repo: "alpha", number: 7))
        }
        #expect(await shell.invocations.allSatisfy { $0.executable == "/test/gh" })
    }

    @Test func `failed Git preparation removes its owned directory`() async throws {
        let shell = MockShellRunner()
        await shell.setResponder { invocation in
            invocation.args.contains("fetch")
                ? .success(pullRequestsShellResult(stderr: "fetch failed", exitCode: 1)) : nil
        }
        let provider = GitHubPullRequestGitDiff(shell: shell, githubCLI: "/test/gh")
        await #expect(throws: PullRequestsServiceError.self) {
            try await provider.prepare(id: .init(owner: "octo", repo: "alpha", number: 7),
                                       comparison: .init(base: String(repeating: "a", count: 40), head: String(repeating: "b", count: 40)))
        }
        let directory = try #require(await shell.invocations.first?.directory)
        #expect(!FileManager.default.fileExists(atPath: directory))
    }

    @Test func `undecodable capture is a failure instead of an empty diff`() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(ShellResult(stdout: "", stdoutData: Data([0xFF]), stderr: "", exitCode: 0,
                                                stdoutWasTruncated: false, stderrWasTruncated: false)))
        let service = GitHubPullRequestsService(shellRunner: shell, executableResolver: DiffTestExecutableResolver())
        await #expect(throws: PullRequestDiffError.self) {
            try await service.fetchDiff(.init(owner: "octo", repo: "alpha", number: 7))
        }
    }

    @Test func `changed commit IDs invalidate cached snapshots`() async throws {
        let shell = MockShellRunner()
        let service = GitHubPullRequestsService(shellRunner: shell, executableResolver: DiffTestExecutableResolver())
        let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        await shell.setResponder { invocation in Self.response(invocation, head: "b") }
        let first = try await service.fetchDiffSnapshot(identifier)
        await shell.setResponder { invocation in Self.response(invocation, head: "c") }
        let second = try await service.fetchDiffSnapshot(identifier)
        #expect(first.id != second.id)
        #expect(second.headOID == String(repeating: "c", count: 40))
        let duplicate = try await service.fetchDiffSnapshot(.init(owner: "octo", repo: "alpha", number: 8))
        #expect(duplicate.id == second.id)
        #expect(await shell.invocations.filter { $0.args.first == "pr" }.count == 2)
    }

    @MainActor
    private func verifyProposal(using service: GitHubPullRequestsService) async throws {
        let fixture = try PullRequestHostToolFixture()
        let host = PullRequestHostToolService(
            modelContext: fixture.modelContext, pullRequestsService: service,
            settingsService: fixture.settingsService, summaryHandoff: fixture.summaryHandoff,
            reviewProposalPreviewCache: PullRequestReviewProposalPreviewCache(fileURL: fixture.previewCacheURL),
            makeProposalID: { PullRequestHostToolFixture.proposalID }
        )
        let result = await host.handle(context: fixture.agentContext(), call: .init(
            name: PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: ["url": .string(PullRequestHostToolFixture.url), "event": .string("comment"),
                        "comments": .array([.object(["path": .string("large"), "line": .number(25_000),
                                                     "side": .string("RIGHT"), "body": .string("Check the final line.")])])]
        ))
        #expect(!result.isError, Comment(rawValue: result.text))
        let preview = try await fixture.waitForSeededPreviewEntry()
        #expect(preview.files.map(\.path) == ["large"])
        #expect(preview.files.first?.hunks.last?.lines.last?.newLineNumber == 25_000)
    }

    private static func response(_ invocation: MockShellRunner.Invocation, head: String) -> MockShellRunner.Response {
        let base = String(repeating: "a", count: 40)
        let head = String(repeating: head, count: 40)
        return .success(pullRequestsShellResult(stdout: invocation.args.first == "api"
            ? "{\"base\":\"\(base)\",\"head\":\"\(head)\"}" : "diff --git a/file b/file\n"))
    }

}

private struct DiffTestExecutableResolver: ExecutablePathResolving {
    func resolveExecutablePath(for candidate: String) async -> String? { "/test/gh" }
}

private actor GitDiffRepositoryRunner: ShellRunner {
    let fixture: GitDiffRepositoryFixture
    let truncated: Bool
    private(set) var rawDiffCalls = 0
    private(set) var gitArguments: [[String]] = []

    init(fixture: GitDiffRepositoryFixture, truncated: Bool) {
        self.fixture = fixture
        self.truncated = truncated
    }

    func run(executable: String, args: [String], in directory: String?, options: ShellRunOptions) async throws -> ShellResult {
        if executable == "/test/gh" {
            if args.contains("graphql") {
                let detail = PullRequestsServiceFixtures.detail.replacingOccurrences(
                    of: "\"number\": 7,",
                    with: "\"number\": 7, \"baseRefOid\": \"\(fixture.comparison.base)\", \"headRefOid\": \"\(fixture.comparison.head)\","
                )
                return pullRequestsShellResult(stdout: detail)
            }
            if args.first == "api" {
                return pullRequestsShellResult(stdout: "{\"base\":\"\(fixture.comparison.base)\",\"head\":\"\(fixture.comparison.head)\"}")
            }
            rawDiffCalls += 1
            return truncated ? pullRequestsShellResult(stdout: "incomplete", stdoutWasTruncated: true)
                : pullRequestsShellResult(stderr: "HTTP 406: diff exceeded the maximum number of lines (20000)", exitCode: 1)
        }
        gitArguments.append(args)
        // Route only the fixture's origin to disk; production still prohibits file transport.
        var localArgs = args.map { $0 == "protocol.file.allow=never" ? "protocol.file.allow=always" : $0 }
        if args.contains("remote"), args.contains("add") { localArgs[localArgs.count - 1] = fixture.directory.path }
        var environment = options.environment ?? [:]
        environment["GIT_DIR"] = fixture.directory.appendingPathComponent(".git").path
        environment["GIT_COMMON_DIR"] = fixture.directory.appendingPathComponent(".git").path
        environment["GIT_CONFIG"] = fixture.directory.appendingPathComponent(".git/config").path
        return try await DefaultShellRunner().run(
            executable: executable, args: localArgs, in: directory, environment: environment,
            timeout: options.timeout, stdoutLimitBytes: options.stdoutLimitBytes,
            stderrLimitBytes: options.stderrLimitBytes, standardInput: options.standardInput
        )
    }
}

private struct GitDiffRepositoryFixture: Sendable {
    let directory: URL
    let comparison: GitHubPullRequestsService.DiffComparison

    static func make() async throws -> Self {
        let directory = try PullRequestDiffSnapshot.makeDirectory()
        let seed = Self(directory: directory, comparison: .init(base: "", head: ""))
        do {
            _ = try await seed.run(["init", "--initial-branch=main"])
            _ = try await seed.run(["config", "user.name", "Test"])
            _ = try await seed.run(["config", "user.email", "test@example.com"])
            for name in ["ordinary", "deleted", "old.txt"] {
                let content = name == "ordinary" ? "before\n" : "\(name)\n"
                try Data(content.utf8).write(to: directory.appendingPathComponent(name))
            }
            try Data([0, 1, 2]).write(to: directory.appendingPathComponent("binary"))
            _ = try await seed.run(["add", "."])
            _ = try await seed.run(["commit", "-m", "base"])
            _ = try await seed.run(["checkout", "-b", "feature"])
            try Data("after\n".utf8).write(to: directory.appendingPathComponent("ordinary"))
            let large = String(repeating: String(repeating: "x", count: 220) + "\n", count: 25_000)
            try Data(large.utf8).write(to: directory.appendingPathComponent("large"))
            try Data([0, 1, 3]).write(to: directory.appendingPathComponent("binary"))
            try FileManager.default.removeItem(at: directory.appendingPathComponent("deleted"))
            try FileManager.default.moveItem(at: directory.appendingPathComponent("old.txt"),
                                            to: directory.appendingPathComponent("renamed\né\t.txt"))
            _ = try await seed.run(["add", "."])
            _ = try await seed.run(["commit", "-m", "change"])
            let head = try await seed.run(["rev-parse", "HEAD"])
            _ = try await seed.run(["update-ref", "refs/pull/7/head", head])
            _ = try await seed.run(["checkout", "main"])
            _ = try await seed.run(["branch", "-D", "feature"])
            try Data("unrelated\n".utf8).write(to: directory.appendingPathComponent("base-only"))
            _ = try await seed.run(["add", "."])
            _ = try await seed.run(["commit", "-m", "advance base"])
            return Self(directory: directory, comparison: .init(base: try await seed.run(["rev-parse", "HEAD"]), head: head))
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func run(_ args: [String]) async throws -> String {
        let result = try await DefaultShellRunner().run(
            executable: "/usr/bin/git", args: ["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgSign=false"] + args,
            in: directory.path, timeout: .seconds(20), stdoutLimitBytes: 64 * 1024, standardInput: .nullDevice
        )
        guard result.succeeded else { throw PullRequestsServiceError.transport(result.stderr) }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
