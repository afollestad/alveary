import Foundation

/// Git quotes tabs, newlines, quotes, and some UTF-8 paths using C escapes. These are path bytes,
/// not JSON escapes; octal sequences must be decoded before interpreting UTF-8.
enum GitDiffPath {
    static func decoded(_ value: String) -> String {
        guard value.first == "\"" else { return value.trimmingCharacters(in: CharacterSet(charactersIn: "\t")) }
        return quoted(Array(value.utf8)[...])?.path ?? value
    }

    static func headerPaths(_ header: String) -> (old: String, new: String)? {
        let text = String(header.dropFirst("diff --git ".count))
        if text.first == "\"", let first = quoted(Array(text.utf8)[...]) {
            let rest = (String(bytes: Array(text.utf8).dropFirst(first.count), encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespaces)
            return (strip(first.path), strip(decoded(rest)))
        }
        if let boundary = text.range(of: " \"b/") {
            return (strip(String(text[..<boundary.lowerBound])), strip(decoded(String(text[boundary.lowerBound...].dropFirst()))))
        }
        // Unquoted names can contain spaces and even " b/". A same-path header is unambiguous
        // when both halves agree; rename metadata supplies distinct names for renames.
        var search = text.startIndex..<text.endIndex
        while let boundary = text.range(of: " b/", range: search) {
            let old = strip(String(text[..<boundary.lowerBound]))
            let new = String(text[boundary.upperBound...])
            if old == new { return (old, new) }
            search = boundary.upperBound..<text.endIndex
        }
        guard let boundary = text.range(of: " b/") else { return nil }
        return (strip(String(text[..<boundary.lowerBound])), String(text[boundary.upperBound...]))
    }

    private static func strip(_ value: String) -> String {
        value.hasPrefix("a/") || value.hasPrefix("b/") ? String(value.dropFirst(2)) : value
    }

    private static func quoted(_ source: ArraySlice<UInt8>) -> (path: String, count: Int)? {
        let bytes = Array(source)
        guard bytes.first == 34 else { return nil }
        var output: [UInt8] = []
        var index = 1
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 {
                guard let path = String(bytes: output, encoding: .utf8) else { return nil }
                return (path, index)
            }
            guard byte == 92, index < bytes.count else { output.append(byte); continue }
            let escaped = bytes[index]
            index += 1
            if (48...55).contains(escaped) {
                var value = Int(escaped - 48)
                for _ in 0..<2 where index < bytes.count && (48...55).contains(bytes[index]) {
                    value = value * 8 + Int(bytes[index] - 48)
                    index += 1
                }
                guard value <= 255 else { return nil }
                output.append(UInt8(value))
            } else {
                let escapes: [UInt8: UInt8] = [97: 7, 98: 8, 116: 9, 110: 10, 118: 11, 102: 12, 114: 13]
                output.append(escapes[escaped] ?? escaped)
            }
        }
        return nil
    }
}
