import Foundation

extension CLIGitService {
    func imageBlob(source: GitImageBlobSource, maxBytes: Int, in directory: String) async throws -> Data {
        switch source {
        case .worktree(let path):
            return try await worktreeImageBlob(path: path, maxBytes: maxBytes, in: directory)
        case .head(let path):
            return try await gitObjectBlob(revision: "HEAD", path: path, maxBytes: maxBytes, in: directory)
        case .index(let path):
            return try await gitObjectBlob(revision: "", path: path, maxBytes: maxBytes, in: directory)
        case .commit(let hash, let path):
            return try await gitObjectBlob(revision: hash, path: path, maxBytes: maxBytes, in: directory)
        case .commitParent(let hash, let path):
            return try await gitObjectBlob(revision: "\(hash)^", path: path, maxBytes: maxBytes, in: directory)
        }
    }

    private func worktreeImageBlob(path: String, maxBytes: Int, in directory: String) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let fileURL = URL(fileURLWithPath: directory).appendingPathComponent(path)
            if let byteCount = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               byteCount > maxBytes {
                throw Self.imageFileTooLarge(maxBytes: maxBytes)
            }

            let data = try Self.boundedFileData(from: fileURL, maxBytes: maxBytes)
            try Task.checkCancellation()
            return data
        }.value
    }

    private func gitObjectBlob(revision: String, path: String, maxBytes: Int, in directory: String) async throws -> Data {
        let spec = revision.isEmpty ? ":\(path)" : "\(revision):\(path)"
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["show", spec],
            in: directory,
            stdoutLimitBytes: maxBytes,
            stderrLimitBytes: 512 * 1024
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        guard !result.stdoutWasTruncated else {
            throw GitError.outputTooLarge("Image blob exceeded \(maxBytes / 1_000_000)MB")
        }
        return result.stdoutData
    }

    private static func boundedFileData(from fileURL: URL, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let chunkSize = 64 * 1024
        var data = Data()
        data.reserveCapacity(min(maxBytes, chunkSize))

        while true {
            try Task.checkCancellation()
            let remainingAllowedBytes = maxBytes - data.count
            let readSize = min(chunkSize, remainingAllowedBytes + 1)
            let chunk = handle.readData(ofLength: readSize)
            if chunk.isEmpty {
                return data
            }

            data.append(chunk)
            if data.count > maxBytes {
                throw imageFileTooLarge(maxBytes: maxBytes)
            }
        }
    }

    private static func imageFileTooLarge(maxBytes: Int) -> GitError {
        GitError.outputTooLarge("Image file exceeded \(maxBytes / 1_000_000)MB")
    }
}
