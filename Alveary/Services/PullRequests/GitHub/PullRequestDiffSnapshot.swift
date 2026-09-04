import Foundation

/// An immutable, disk-backed diff. Keeping byte positions separate from patch text lets tools
/// resume inside a hunk or a single long line without retaining the whole diff in memory.
final class PullRequestDiffSnapshot: Sendable {
    struct Line: Sendable {
        let offset: Int
        let length: Int
        let oldLine: Int?
        let newLine: Int?
    }

    struct File: Sendable {
        let metadata: DiffFile
        let offset: Int
        let length: Int
        let patchOffset: Int
        let lines: [Line]
        let additions: Int
        let deletions: Int

        var patchLength: Int { offset + length - patchOffset }
    }

    struct Fragment: Sendable {
        let text: String
        let nextOffset: Int
        let oldLine: Int?
        let newLine: Int?
        let startsMidLine: Bool
        let endsMidLine: Bool
    }

    let id = UUID().uuidString
    let url: URL
    let files: [File]
    let byteCount: Int
    let baseOID: String?
    let headOID: String?

    init(url: URL, directory: URL, baseOID: String? = nil, headOID: String? = nil) throws {
        self.url = url
        self.directory = directory
        self.baseOID = baseOID
        self.headOID = headOID
        let index = try Self.index(url: url)
        guard index.byteCount == 0 || !index.files.isEmpty,
              index.files.allSatisfy({ $0.metadata.oldPath != nil || $0.metadata.newPath != nil }) else {
            throw PullRequestDiffError.invalidEncoding
        }
        files = index.files
        byteCount = index.byteCount
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlvearyPRDiff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        return directory
    }

    static func make(text: String, baseOID: String? = nil, headOID: String? = nil) throws -> PullRequestDiffSnapshot {
        let directory = try makeDirectory()
        do {
            let url = directory.appendingPathComponent("changes.diff")
            try Data(text.utf8).write(to: url)
            return try PullRequestDiffSnapshot(url: url, directory: directory, baseOID: baseOID, headOID: headOID)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func text(maxBytes: Int) throws -> String {
        guard byteCount <= maxBytes else { throw PullRequestsServiceError.responseTooLarge }
        return try read(offset: 0, length: byteCount)
    }

    /// Only files containing proposed or pending comments need to be materialized for anchoring.
    func parsedFiles(paths: Set<String>) throws -> [DiffFile] {
        try files.filter { paths.contains($0.metadata.path) || $0.metadata.oldPath.map(paths.contains) == true }
            .flatMap { try DiffParser.parse(read(offset: $0.offset, length: $0.length)) }
    }

    func fragment(file: Int, offset: Int, maxBytes: Int) throws -> Fragment {
        let entry = files[file]
        let absolute = entry.patchOffset + offset
        let length = min(maxBytes, entry.patchLength - offset)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(absolute))
        var data = try handle.read(upToCount: length) ?? Data()
        // A cursor always resumes at a UTF-8 boundary, including inside a long source line.
        while !data.isEmpty, String(data: data, encoding: .utf8) == nil, data.count > length - 4 {
            data.removeLast()
        }
        guard let text = String(data: data, encoding: .utf8), !data.isEmpty || length == 0 else {
            throw PullRequestDiffError.invalidEncoding
        }
        let line = entry.lines.last { $0.offset <= absolute }
        let end = absolute + data.count
        return Fragment(
            text: text, nextOffset: offset + data.count,
            oldLine: line?.oldLine, newLine: line?.newLine,
            startsMidLine: line.map { absolute > $0.offset } ?? false,
            endsMidLine: end < entry.offset + entry.length && data.last != 10
        )
    }

    private let directory: URL

    private func read(offset: Int, length: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: length) ?? Data()
        guard data.count == length, let text = String(data: data, encoding: .utf8) else {
            throw PullRequestDiffError.invalidEncoding
        }
        return text
    }
}

enum PullRequestDiffError: Error, LocalizedError, Sendable {
    case invalidEncoding
    case expired
    case preparationTimedOut
    case revisionChanged
    case invalidComparison

    var errorDescription: String? {
        switch self {
        case .invalidEncoding: "The pull request diff could not be read completely as UTF-8."
        case .expired: "This diff cursor expired. Call get_pr_diff without cursor to start again."
        case .preparationTimedOut: "Preparing the complete pull request diff exceeded ten minutes. Retry get_pr_diff without cursor."
        case .revisionChanged: "The pull request changed while its diff was being read. Call get_pr_diff without cursor to review it again."
        case .invalidComparison: "GitHub did not provide a valid base and head commit for this pull request."
        }
    }
}
