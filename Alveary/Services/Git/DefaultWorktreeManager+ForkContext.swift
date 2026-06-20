import Darwin
import Foundation

extension DefaultWorktreeManager {
    func prepareForkContext(sourcePath: String, worktreePath: String) async throws {
        try await applyTrackedForkChanges(from: sourcePath, to: worktreePath)
        try await copyWorktreeIncludedIgnoredFiles(from: sourcePath, to: worktreePath)
    }

    private func applyTrackedForkChanges(from sourcePath: String, to worktreePath: String) async throws {
        let diff = try await shell.run(
            executable: "/usr/bin/git",
            args: ["diff", "--binary", "HEAD", "--"],
            in: sourcePath
        )
        guard diff.succeeded else {
            throw Self.makeGitError(from: diff)
        }
        guard !diff.stdoutData.isEmpty else {
            return
        }

        let patchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlvearyWorktreeFork-\(UUID().uuidString).patch")
        try diff.stdoutData.write(to: patchURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: patchURL) }

        let applyResult = try await shell.run(
            executable: "/usr/bin/git",
            args: ["apply", "--whitespace=nowarn", "--", patchURL.path],
            in: worktreePath
        )
        guard applyResult.succeeded else {
            throw Self.makeGitError(from: applyResult)
        }
    }

    private func copyWorktreeIncludedIgnoredFiles(from sourcePath: String, to worktreePath: String) async throws {
        let sourceURL = URL(fileURLWithPath: sourcePath, isDirectory: true)
        let includeURL = sourceURL.appendingPathComponent(".worktreeinclude")
        guard FileManager.default.fileExists(atPath: includeURL.path) else {
            return
        }

        let contents = try String(contentsOf: includeURL, encoding: .utf8)
        for pattern in worktreeIncludePatterns(from: contents) {
            try await copyWorktreeIncludeMatches(pattern, sourceURL: sourceURL, worktreePath: worktreePath)
        }
    }

    private func worktreeIncludePatterns(from contents: String) -> [String] {
        contents
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                    return nil
                }
                return trimmed
            }
    }

    private func copyWorktreeIncludeMatches(
        _ pattern: String,
        sourceURL: URL,
        worktreePath: String
    ) async throws {
        let fullPattern = sourceURL.appendingPathComponent(pattern).path
        var globResult = glob_t()
        defer { globfree(&globResult) }

        guard glob(fullPattern, GLOB_MARK, nil, &globResult) == 0 else {
            return
        }

        for index in 0..<Int(globResult.gl_pathc) {
            guard let matchPointer = globResult.gl_pathv[index],
                  let matchedPath = String(validatingCString: matchPointer) else {
                continue
            }
            try await copyWorktreeIncludedPath(
                URL(fileURLWithPath: matchedPath),
                sourceURL: sourceURL,
                worktreePath: worktreePath
            )
        }
    }

    private func copyWorktreeIncludedPath(
        _ matchedURL: URL,
        sourceURL: URL,
        worktreePath: String
    ) async throws {
        let resourceValues = try matchedURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard resourceValues.isSymbolicLink != true else {
            return
        }

        if resourceValues.isDirectory == true {
            try await copyWorktreeIncludedDirectory(matchedURL, sourceURL: sourceURL, worktreePath: worktreePath)
        } else {
            try await copyWorktreeIncludedFile(matchedURL, sourceURL: sourceURL, worktreePath: worktreePath)
        }
    }

    private func copyWorktreeIncludedDirectory(
        _ directoryURL: URL,
        sourceURL: URL,
        worktreePath: String
    ) async throws {
        for fileURL in try regularFiles(in: directoryURL) {
            try await copyWorktreeIncludedFile(fileURL, sourceURL: sourceURL, worktreePath: worktreePath)
        }
    }

    private func regularFiles(in directoryURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if resourceValues.isDirectory == true || resourceValues.isSymbolicLink == true {
                continue
            }
            files.append(fileURL)
        }
        return files
    }

    private func copyWorktreeIncludedFile(
        _ fileURL: URL,
        sourceURL: URL,
        worktreePath: String
    ) async throws {
        guard let relativePath = relativePath(for: fileURL, under: sourceURL),
              await isGitIgnored(relativePath, in: sourceURL.path) else {
            return
        }

        let destinationURL = URL(fileURLWithPath: worktreePath, isDirectory: true)
            .appendingPathComponent(relativePath)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            return
        }

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
    }

    private func isGitIgnored(_ relativePath: String, in sourcePath: String) async -> Bool {
        let result = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["check-ignore", "--quiet", "--", relativePath],
            in: sourcePath
        )
        return result?.exitCode == 0
    }

    private func relativePath(for fileURL: URL, under sourceURL: URL) -> String? {
        let sourcePath = sourceURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(sourcePath + "/") else {
            return nil
        }
        return String(filePath.dropFirst(sourcePath.count + 1))
    }
}
