import Foundation

/// Fetches objects into a private bare repository, never into a user's checkout. Command-local
/// authentication also applies to Git's lazy blob fetches without writing credentials to disk.
struct GitHubPullRequestGitDiff: Sendable {
    let shell: any ShellRunner
    let githubCLI: String
    var git = "/usr/bin/git"

    func prepare(
        id: PullRequestIdentifier,
        comparison: GitHubPullRequestsService.DiffComparison
    ) async throws -> PullRequestDiffSnapshot {
        let directory = try PullRequestDiffSnapshot.makeDirectory()
        do {
            let repository = directory.appendingPathComponent("objects.git")
            _ = try await run(["init", "--bare", "--template=", repository.path], in: directory)
            let remote = "https://github.com/\(id.nameWithOwner).git"
            _ = try await run(["remote", "add", "origin", remote], in: repository)
            _ = try await run(["config", "remote.origin.promisor", "true"], in: repository)
            _ = try await run(["config", "remote.origin.partialclonefilter", "blob:none"], in: repository)
            _ = try await run([
                "fetch", "--no-tags", "--no-recurse-submodules", "--filter=blob:none", "origin",
                comparison.base, comparison.head, "refs/pull/\(id.number)/head:refs/heads/pull-request"
            ], in: repository)
            let mergeBase = try await run(["merge-base", comparison.base, comparison.head], in: repository)
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !mergeBase.isEmpty else { throw PullRequestDiffError.invalidComparison }
            let url = directory.appendingPathComponent("changes.diff")
            _ = try await run([
                "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--find-renames", "--unified=3",
                "--src-prefix=a/", "--dst-prefix=b/", "--output=\(url.path)", mergeBase, comparison.head, "--"
            ], in: repository)
            try Task.checkCancellation()
            let indexing = Task.detached {
                try PullRequestDiffSnapshot(url: url, directory: directory, baseOID: comparison.base, headOID: comparison.head)
            }
            return try await withTaskCancellationHandler {
                try await indexing.value
            } onCancel: { indexing.cancel() }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func run(_ args: [String], in directory: URL) async throws -> ShellResult {
        let helper = "!'\(githubCLI.replacingOccurrences(of: "'", with: "'\\''"))' auth git-credential"
        let configuration = [
            "-c", "credential.helper=", "-c", "credential.helper=\(helper)",
            "-c", "core.hooksPath=/dev/null", "-c", "core.attributesFile=/dev/null",
            "-c", "core.quotePath=false", "-c", "protocol.file.allow=never"
        ]
        // A terminal-launched app can inherit repository overrides; cwd alone does not isolate Git.
        let unset = ["GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
                     "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_INDEX_FILE", "GIT_SHALLOW_FILE", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS"]
            .flatMap { ["-u", $0] }
        let result = try await shell.run(
            executable: "/usr/bin/env", args: unset + [git] + configuration + args, in: directory.path,
            environment: ["GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
                          "GIT_TERMINAL_PROMPT": "0", "GIT_CONFIG_COUNT": "0", "GIT_LFS_SKIP_SMUDGE": "1"],
            timeout: .seconds(600), stdoutLimitBytes: 64 * 1024, stderrLimitBytes: 64 * 1024,
            standardInput: .nullDevice
        )
        guard result.succeeded else { throw GitHubPullRequestsService.makeError(from: result) }
        guard !result.stdoutWasTruncated else { throw PullRequestsServiceError.responseTooLarge }
        return result
    }
}
