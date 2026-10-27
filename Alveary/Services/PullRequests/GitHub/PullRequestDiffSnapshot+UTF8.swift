import Foundation

/// Git copies a text-detected file's bytes into a diff verbatim, so binary data without a NUL byte, or text in another
/// encoding, would fail every strict read of the snapshot. Replacement never consumes a newline byte, so line numbers still
/// match GitHub's.
extension PullRequestDiffSnapshot {
    static func repairedText(_ data: Data) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: data, as: UTF8.self)
    }

    static func repairUTF8(at url: URL) throws {
        var isValid = true
        try forEachUTF8Block(at: url) { block in
            isValid = String(data: block, encoding: .utf8) != nil
            return isValid
        }
        guard !isValid else { return }
        let repaired = url.appendingPathExtension("repaired")
        try Data().write(to: repaired)
        do {
            let output = try FileHandle(forWritingTo: repaired)
            defer { try? output.close() }
            try forEachUTF8Block(at: url) { block in
                try output.write(contentsOf: Data(repairedText(block).utf8))
                return true
            }
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: repaired)
    }

    /// Holds back a sequence split across reads, so each block decodes exactly as it would within the whole file.
    private static func forEachUTF8Block(at url: URL, _ body: (Data) throws -> Bool) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var carry = Data()
        while let read = try handle.read(upToCount: 64 * 1024), !read.isEmpty {
            try Task.checkCancellation()
            var block = carry + read
            let incomplete = incompleteSequenceLength(block)
            carry = Data(block.suffix(incomplete))
            block.removeLast(incomplete)
            guard try body(block) else { return }
        }
        if !carry.isEmpty { _ = try body(carry) }
    }

    private static func incompleteSequenceLength(_ data: Data) -> Int {
        for distance in 1..<min(4, data.count + 1) {
            let byte = data[data.index(data.endIndex, offsetBy: -distance)]
            guard byte & 0xC0 == 0x80 else {
                let length = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
                return length > distance ? distance : 0
            }
        }
        return 0
    }
}
