import Foundation

extension CLIGitService {
    func isLikelyBinary(_ data: Data) -> Bool {
        guard !data.isEmpty else {
            return false
        }

        if data.contains(0) {
            return true
        }

        return false
    }

    func parseDiffStats(_ output: String) -> DiffStats {
        output
            .split(separator: "\n")
            .reduce(.empty) { partialResult, line in
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count >= 2,
                      let additions = Int(parts[0]),
                      let deletions = Int(parts[1]) else {
                    return partialResult
                }

                return partialResult.adding(DiffStats(additions: additions, deletions: deletions))
            }
    }

    func untrackedDiffStats(in directory: String, knownStatuses: [FileStatus]?) async throws -> DiffStats {
        let statuses: [FileStatus]
        if let knownStatuses {
            statuses = knownStatuses
        } else {
            statuses = try await status(in: directory)
        }
        let untrackedPaths = statuses
            .filter { $0.status == .untracked && !$0.isStaged }
            .map(\.path)

        return untrackedPaths.reduce(.empty) { partialResult, path in
            partialResult.adding(untrackedDiffStats(for: path, in: directory))
        }
    }

    func untrackedDiffStats(for path: String, in directory: String) -> DiffStats {
        let fileURL = URL(fileURLWithPath: directory).appendingPathComponent(path)
        let byteCount = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard byteCount <= Self.untrackedDiffMaxFileSize,
              let data = try? Data(contentsOf: fileURL),
              !isLikelyBinary(data),
              let content = String(bytes: data, encoding: .utf8) else {
            return .empty
        }

        return DiffStats(additions: addedTextDiffContent(for: content).lineCount, deletions: 0)
    }

    // Shared by toolbar stats and lower-pane synthetic previews so untracked
    // files do not drift from Git's new-file hunk semantics.
    func addedTextDiffContent(for content: String) -> AddedTextDiffContent {
        guard !content.isEmpty else {
            return AddedTextDiffContent(lineCount: 0, body: "")
        }

        // Git reports untracked text like an intent-to-add file: a final newline
        // terminates the last added line, not an extra blank added line.
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let hasFinalNewline = content.last == "\n"
        if hasFinalNewline {
            lines.removeLast()
        }

        var body = lines.map { "+\($0)" }.joined(separator: "\n")
        if !hasFinalNewline {
            body += "\n\\ No newline at end of file"
        }

        return AddedTextDiffContent(lineCount: lines.count, body: body)
    }
}

struct AddedTextDiffContent {
    let lineCount: Int
    let body: String
}
