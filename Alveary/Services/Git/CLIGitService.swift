import Foundation

final class CLIGitService: GitService {
    static let untrackedDiffMaxFileSize = 100_000

    let shell: ShellRunner

    init(shell: ShellRunner) {
        self.shell = shell
    }
    func status(in directory: String) async throws -> [FileStatus] {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["--no-optional-locks", "status", "--porcelain=v2", "-z", "--no-ahead-behind", "--untracked-files=all"],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        return parseStatus(result.stdout)
    }

    func diffStats(in directory: String, knownStatuses: [FileStatus]?) async throws -> DiffStats {
        let unstaged = try await diffStats(args: ["diff", "--numstat", "--"], in: directory)
        let staged = try await diffStats(args: ["diff", "--cached", "--numstat", "--"], in: directory)
        let untracked = (try? await untrackedDiffStats(in: directory, knownStatuses: knownStatuses)) ?? .empty
        return unstaged.adding(staged).adding(untracked)
    }

    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String {
        guard !paths.isEmpty else {
            return ""
        }

        var args = ["diff", "--no-color", "--unified=2000"]
        if scope == .staged {
            args.append("--cached")
        }
        args += ["--"] + paths

        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: args,
            in: directory,
            stdoutLimitBytes: 30 * 1024 * 1024,
            stderrLimitBytes: 512 * 1024
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        guard !result.stdoutWasTruncated else {
            throw GitError.outputTooLarge("Diff output exceeded 30MB")
        }
        return result.stdout
    }

    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String {
        let fileURL = URL(fileURLWithPath: directory).appendingPathComponent(path)
        let byteCount = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard byteCount <= Self.untrackedDiffMaxFileSize else {
            throw GitError.outputTooLarge("Untracked file is too large to preview (>100KB)")
        }

        let data = try Data(contentsOf: fileURL)
        guard !isLikelyBinary(data),
              let content = String(bytes: data, encoding: .utf8) else {
            return """
            diff --git a/\(path) b/\(path)
            new file mode 100644
            Binary files /dev/null and b/\(path) differ
            """
        }

        let addedText = addedTextDiffContent(for: content)
        guard addedText.lineCount > 0 else {
            return """
            diff --git a/\(path) b/\(path)
            new file mode 100644
            """
        }

        return """
        diff --git a/\(path) b/\(path)
        new file mode 100644
        --- /dev/null
        +++ b/\(path)
        @@ -0,0 +1,\(addedText.lineCount) @@
        \(addedText.body)
        """
    }

    func stage(paths: [String], in directory: String) async throws {
        guard !paths.isEmpty else {
            return
        }

        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["add", "--"] + paths,
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func unstage(paths: [String], in directory: String) async throws {
        guard !paths.isEmpty else {
            return
        }

        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["reset", "HEAD", "--"] + paths,
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
    }

    func discard(paths: [String], scope: DiscardScope, in directory: String) async throws {
        guard !paths.isEmpty else {
            return
        }

        let statuses = try await status(in: directory)
        let untrackedPaths = Set(statuses.filter { $0.status == .untracked }.map(\.path))
        let trackedPaths = paths.filter { !untrackedPaths.contains($0) }

        if !trackedPaths.isEmpty {
            let restoreArgs: [String]
            switch scope {
            case .all:
                restoreArgs = ["restore", "--source=HEAD", "--staged", "--worktree", "--"]
            case .worktreeOnly:
                restoreArgs = ["restore", "--worktree", "--"]
            }

            let result = try await shell.run(
                executable: "/usr/bin/git",
                args: restoreArgs + trackedPaths,
                in: directory
            )
            guard result.succeeded else {
                throw Self.makeError(from: result)
            }
        }

        let fileManager = FileManager.default
        for path in paths where untrackedPaths.contains(path) {
            let fileURL = URL(fileURLWithPath: directory).appendingPathComponent(path)
            try? fileManager.removeItem(at: fileURL)
        }
    }

    func log(in directory: String, limit: Int) async throws -> [CommitInfo] {
        guard limit > 0 else {
            return []
        }

        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["log", "--pretty=format:%H%n%s%n%an%n%aI", "-\(limit)"],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        return parseLog(result.stdout)
    }

    func currentBranch(in directory: String) async throws -> String {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["rev-parse", "--abbrev-ref", "HEAD"],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func currentHeadHash(in directory: String) async throws -> String {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["rev-parse", "--verify", "HEAD"],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func listFiles(in directory: String) async throws -> [String] {
        // `-co --exclude-standard` returns tracked plus untracked-but-not-ignored
        // files so agent-created files show up in @-mention autocomplete before
        // they're committed.
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["ls-files", "-co", "--exclude-standard"],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        return result.stdout.split(separator: "\n").map(String.init)
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        let compareRef = try await aheadCompareRef(baseBranch: baseBranch, remoteName: remoteName, in: directory)

        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["rev-list", "\(compareRef)..HEAD", "--count"],
            in: directory
        )
        guard result.succeeded else {
            return 0
        }
        return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func commitsAheadOfBaseDetails(baseBranch: String, remoteName: String?, in directory: String) async throws -> [CommitInfo] {
        let compareRef = try await aheadCompareRef(baseBranch: baseBranch, remoteName: remoteName, in: directory)
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["log", "--pretty=format:%H%n%s%n%an%n%aI", "\(compareRef)..HEAD"],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        return parseLog(result.stdout)
    }

    func diffForCommit(hash: String, in directory: String) async throws -> String {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["show", "--no-color", "--unified=2000", "--format=", hash],
            in: directory,
            stdoutLimitBytes: 30 * 1024 * 1024,
            stderrLimitBytes: 512 * 1024
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        guard !result.stdoutWasTruncated else {
            throw GitError.outputTooLarge("Commit diff output exceeded 30MB")
        }
        return result.stdout
    }
}

extension CLIGitService {
    func aheadCompareRef(baseBranch: String, remoteName: String?, in directory: String) async throws -> String {
        // Keep ahead counts and ahead commit lists aligned, including older projects that
        // predate persisted remote metadata but still have a usable branch upstream.
        if let remoteName,
           await remoteTrackingRefExists(remoteName: remoteName, baseBranch: baseBranch, in: directory) {
            return "\(remoteName)/\(baseBranch)"
        }

        if remoteName == nil,
           let upstream = await currentBranchUpstream(in: directory) {
            return upstream
        }

        if remoteName == nil,
           await remoteTrackingRefExists(remoteName: "origin", baseBranch: baseBranch, in: directory) {
            return "origin/\(baseBranch)"
        }

        return baseBranch
    }

    func remoteTrackingRefExists(remoteName: String, baseBranch: String, in directory: String) async -> Bool {
        let remoteRef = "refs/remotes/\(remoteName)/\(baseBranch)"
        let remoteExists = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["show-ref", "--verify", "--quiet", remoteRef],
            in: directory
        )
        return remoteExists?.succeeded == true
    }

    func currentBranchUpstream(in directory: String) async -> String? {
        let upstream = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            in: directory
        )
        guard upstream?.succeeded == true else {
            return nil
        }

        let ref = upstream?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ref.isEmpty ? nil : ref
    }

    func diffStats(args: [String], in directory: String) async throws -> DiffStats {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: args,
            in: directory,
            stdoutLimitBytes: 1024 * 1024,
            stderrLimitBytes: 512 * 1024
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        return parseDiffStats(result.stdout)
    }

    static func makeError(from result: ShellResult) -> GitError {
        let combined = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "Git command failed"

        if combined.localizedCaseInsensitiveContains("not a git repository") {
            return .notARepository
        }

        return .commandFailed(combined)
    }

    func parseStatus(_ output: String) -> [FileStatus] {
        guard !output.isEmpty else {
            return []
        }

        let entries = output.split(separator: "\0", omittingEmptySubsequences: true)
        var statuses: [FileStatus] = []
        var index = 0

        while index < entries.count {
            let (entryStatuses, entriesConsumed) = parseStatusEntry(at: index, in: entries)
            statuses.append(contentsOf: entryStatuses)
            index += entriesConsumed
        }

        return statuses
    }

    func parseStatusEntry(at index: Int, in entries: [Substring]) -> (statuses: [FileStatus], entriesConsumed: Int) {
        let line = String(entries[index])

        if line.hasPrefix("1 ") {
            return (parseOrdinaryStatusLine(line), 1)
        }

        if line.hasPrefix("2 ") {
            let originalPath = index + 1 < entries.count ? String(entries[index + 1]) : nil
            return (parseRenamedStatusLine(line, originalPath: originalPath), min(2, entries.count - index))
        }

        if line.hasPrefix("u ") {
            return (parseUnmergedStatusLine(line), 1)
        }

        if line.hasPrefix("? ") {
            return (parseUntrackedStatusLine(line), 1)
        }

        return ([], 1)
    }

    func parseOrdinaryStatusLine(_ line: String) -> [FileStatus] {
        let parts = line.split(separator: " ", maxSplits: 8)
        guard parts.count >= 9 else {
            return []
        }

        var statuses: [FileStatus] = []
        appendOrdinaryStatuses(
            statusPair: String(parts[1]),
            path: String(parts[8]),
            originalPath: nil,
            into: &statuses
        )
        return statuses
    }

    func parseRenamedStatusLine(_ line: String, originalPath: String?) -> [FileStatus] {
        let parts = line.split(separator: " ", maxSplits: 9)
        guard parts.count >= 10 else {
            return []
        }

        var statuses: [FileStatus] = []
        appendOrdinaryStatuses(
            statusPair: String(parts[1]),
            path: String(parts[9]),
            originalPath: originalPath,
            into: &statuses
        )
        return statuses
    }

    func parseUnmergedStatusLine(_ line: String) -> [FileStatus] {
        let parts = line.split(separator: " ", maxSplits: 10)
        guard parts.count >= 11 else {
            return []
        }

        return [
            FileStatus(
                path: String(parts[10]),
                originalPath: nil,
                status: .unmerged,
                isStaged: false
            )
        ]
    }

    func parseUntrackedStatusLine(_ line: String) -> [FileStatus] {
        [
            FileStatus(
                path: String(line.dropFirst(2)),
                originalPath: nil,
                status: .untracked,
                isStaged: false
            )
        ]
    }

    func appendOrdinaryStatuses(
        statusPair: String,
        path: String,
        originalPath: String?,
        into statuses: inout [FileStatus]
    ) {
        guard let indexStatus = statusPair.first,
              let worktreeStatus = statusPair.last else {
            return
        }

        if indexStatus != "." {
            statuses.append(
                FileStatus(
                    path: path,
                    originalPath: originalPath,
                    status: status(from: indexStatus),
                    isStaged: true
                )
            )
        }

        if worktreeStatus != "." {
            statuses.append(
                FileStatus(
                    path: path,
                    originalPath: originalPath,
                    status: status(from: worktreeStatus),
                    isStaged: false
                )
            )
        }
    }

    func status(from character: Character) -> FileStatus.Status {
        switch character {
        case "A":
            return .added
        case "C":
            return .copied
        case "D":
            return .deleted
        case "R":
            return .renamed
        case "M":
            return .modified
        default:
            return .modified
        }
    }

    func parseLog(_ output: String) -> [CommitInfo] {
        let formatter = ISO8601DateFormatter()
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var commits: [CommitInfo] = []
        var index = 0

        while index + 3 < lines.count {
            let date = formatter.date(from: lines[index + 3]) ?? .distantPast
            commits.append(
                CommitInfo(
                    hash: lines[index],
                    message: lines[index + 1],
                    author: lines[index + 2],
                    date: date
                )
            )
            index += 4
        }

        return commits
    }
}
