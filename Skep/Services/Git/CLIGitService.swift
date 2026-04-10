import Foundation

final class CLIGitService: GitService, @unchecked Sendable {
    private let shell: ShellRunner

    init(shell: ShellRunner) {
        self.shell = shell
    }

    func status(in directory: String) async throws -> [FileStatus] {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["--no-optional-locks", "status", "--porcelain=v2", "-z", "--no-ahead-behind"],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        return parseStatus(result.stdout)
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
        guard byteCount <= 100_000 else {
            throw GitError.outputTooLarge("Untracked file is too large to preview (>100KB)")
        }

        let data = try Data(contentsOf: fileURL)
        let content = String(bytes: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let lineCount = max(lines.count, 1)
        let body = lines.map { "+\($0)" }.joined(separator: "\n")

        return """
        diff --git a/\(path) b/\(path)
        new file mode 100644
        --- /dev/null
        +++ b/\(path)
        @@ -0,0 +1,\(lineCount) @@
        \(body)
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

    func discard(paths: [String], in directory: String) async throws {
        guard !paths.isEmpty else {
            return
        }

        let statuses = try await status(in: directory)
        let untrackedPaths = Set(statuses.filter { $0.status == .untracked }.map(\.path))
        let trackedPaths = paths.filter { !untrackedPaths.contains($0) }

        if !trackedPaths.isEmpty {
            let result = try await shell.run(
                executable: "/usr/bin/git",
                args: ["restore", "--source=HEAD", "--staged", "--worktree", "--"] + trackedPaths,
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

    func listFiles(in directory: String) async throws -> [String] {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["ls-files"],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        return result.stdout.split(separator: "\n").map(String.init)
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        let compareRef: String
        if let remoteName {
            let remoteRef = "refs/remotes/\(remoteName)/\(baseBranch)"
            let remoteExists = try? await shell.run(
                executable: "/usr/bin/git",
                args: ["show-ref", "--verify", "--quiet", remoteRef],
                in: directory
            )
            compareRef = remoteExists?.succeeded == true ? "\(remoteName)/\(baseBranch)" : baseBranch
        } else {
            compareRef = baseBranch
        }

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
}

private extension CLIGitService {
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

        var statuses: [FileStatus] = []
        let entries = output.split(separator: "\0", omittingEmptySubsequences: true)
        var index = 0

        while index < entries.count {
            let line = String(entries[index])

            if line.hasPrefix("1 ") {
                let parts = line.split(separator: " ", maxSplits: 8)
                guard parts.count >= 9 else {
                    index += 1
                    continue
                }

                let statusPair = String(parts[1])
                let path = String(parts[8])
                appendOrdinaryStatuses(
                    statusPair: statusPair,
                    path: path,
                    originalPath: nil,
                    into: &statuses
                )
            } else if line.hasPrefix("2 ") {
                let parts = line.split(separator: " ", maxSplits: 9)
                guard parts.count >= 10 else {
                    index += 1
                    continue
                }

                let statusPair = String(parts[1])
                let path = String(parts[9])
                let originalPath = index + 1 < entries.count ? String(entries[index + 1]) : nil
                appendOrdinaryStatuses(
                    statusPair: statusPair,
                    path: path,
                    originalPath: originalPath,
                    into: &statuses
                )
                index += 1
            } else if line.hasPrefix("u ") {
                let parts = line.split(separator: " ", maxSplits: 10)
                guard parts.count >= 11 else {
                    index += 1
                    continue
                }

                statuses.append(
                    FileStatus(
                        path: String(parts[10]),
                        originalPath: nil,
                        status: .unmerged,
                        isStaged: false
                    )
                )
            } else if line.hasPrefix("? ") {
                statuses.append(
                    FileStatus(
                        path: String(line.dropFirst(2)),
                        originalPath: nil,
                        status: .untracked,
                        isStaged: false
                    )
                )
            }

            index += 1
        }

        return statuses
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
