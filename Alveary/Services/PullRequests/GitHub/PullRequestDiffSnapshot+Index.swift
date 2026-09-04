import Foundation

/// Scans fixed-size blocks; even a multi-megabyte source line only retains its short prefix.
extension PullRequestDiffSnapshot {
    static func index(url: URL) throws -> (files: [File], byteCount: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var builder = DiffSnapshotIndexBuilder()
        var prefix = Data()
        var lineStart = 0
        var position = 0
        while let block = try handle.read(upToCount: 64 * 1024), !block.isEmpty {
            try Task.checkCancellation()
            for byte in block {
                if prefix.count < 16 * 1024 { prefix.append(byte) }
                position += 1
                if byte == 10 {
                    try builder.consume(prefix: prefix, offset: lineStart, length: position - lineStart)
                    lineStart = position
                    prefix.removeAll(keepingCapacity: true)
                }
            }
        }
        if position > lineStart {
            try builder.consume(prefix: prefix, offset: lineStart, length: position - lineStart)
        }
        builder.finish(at: position)
        return (builder.files, position)
    }
}

private struct DiffSnapshotIndexBuilder {
    var files: [PullRequestDiffSnapshot.File] = []
    var metadata = ""
    var start = 0
    var patchStart: Int?
    var lines: [PullRequestDiffSnapshot.Line] = []
    var oldLine = 0
    var newLine = 0
    var additions = 0
    var deletions = 0

    mutating func consume(prefix: Data, offset: Int, length: Int) throws {
        let text = try Self.decodedPrefix(prefix)
        if text.hasPrefix("diff --git ") {
            guard prefix.count == length else { throw PullRequestsServiceError.responseTooLarge }
            finish(at: offset)
            metadata = text
            start = offset
            return
        }
        guard !metadata.isEmpty else { return }
        if text.hasPrefix("@@ ") {
            if patchStart == nil { patchStart = offset }
            let parsed = DiffParser.parse("diff --git a/file b/file\n" + text)
            guard let hunk = parsed.first?.hunks.first else { throw PullRequestDiffError.invalidEncoding }
            oldLine = hunk.oldStart
            newLine = hunk.newStart
            lines.append(.init(offset: offset, length: length, oldLine: oldLine, newLine: newLine))
        } else if patchStart != nil {
            consumePatchLine(prefix: prefix, offset: offset, length: length)
        } else {
            guard prefix.count == length else { throw PullRequestsServiceError.responseTooLarge }
            metadata += text
        }
    }

    mutating func finish(at end: Int) {
        if let file = DiffParser.parse(metadata).first {
            files.append(.init(metadata: file, offset: start, length: end - start,
                               patchOffset: patchStart ?? end, lines: lines,
                               additions: additions, deletions: deletions))
        }
        metadata = ""
        patchStart = nil
        lines = []
        additions = 0
        deletions = 0
    }

    private mutating func consumePatchLine(prefix: Data, offset: Int, length: Int) {
        let first = prefix.first
        lines.append(.init(offset: offset, length: length,
                           oldLine: first == 43 ? nil : oldLine,
                           newLine: first == 45 ? nil : newLine))
        switch first {
        case 43: additions += 1; newLine += 1
        case 45: deletions += 1; oldLine += 1
        case 32: oldLine += 1; newLine += 1
        default: break
        }
    }

    private static func decodedPrefix(_ prefix: Data) throws -> String {
        var bytes = prefix
        for _ in 0..<3 where String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        guard let text = String(bytes: bytes, encoding: .utf8) else { throw PullRequestDiffError.invalidEncoding }
        return text
    }

}
