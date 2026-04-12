import Foundation

enum DiffParser {
    static func parse(_ diffOutput: String) -> [DiffFile] {
        var files: [DiffFile] = []
        let lines = diffOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0

        while index < lines.count {
            guard lines[index].hasPrefix("diff --git ") else {
                index += 1
                continue
            }

            var fileBuilder = DiffFileBuilder(headerLine: lines[index])
            index += 1

            fileBuilder.consumeMetadata(in: lines, index: &index)
            fileBuilder.consumePathMarkers(in: lines, index: &index)
            fileBuilder.consumeHunks(in: lines, index: &index)

            files.append(fileBuilder.build())
        }

        return files
    }

    fileprivate static func parseHunk(lines: [String], index: inout Int) -> DiffHunk? {
        guard let header = parseHunkHeader(lines[index]) else {
            index += 1
            return nil
        }
        index += 1

        let diffLines = parseHunkLines(
            lines: lines,
            index: &index,
            oldLineNumber: header.oldStart,
            newLineNumber: header.newStart
        )

        return DiffHunk(
            oldStart: header.oldStart,
            oldCount: header.oldCount,
            newStart: header.newStart,
            newCount: header.newCount,
            header: header.header,
            lines: diffLines
        )
    }

    private static func parseHunkHeader(_ headerLine: String) -> HunkHeader? {
        guard headerLine.hasPrefix("@@ ") else {
            return nil
        }

        let searchStart = headerLine.index(headerLine.startIndex, offsetBy: 3)
        guard let closingRange = headerLine.range(of: " @@", range: searchStart..<headerLine.endIndex) else {
            return nil
        }

        let rangeString = String(headerLine[searchStart..<closingRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let parts = rangeString.split(separator: " ")
        guard parts.count == 2,
              let oldRange = parseRange(parts[0]),
              let newRange = parseRange(parts[1]) else {
            return nil
        }

        let headerContext = String(headerLine[closingRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return HunkHeader(
            oldStart: oldRange.start,
            oldCount: oldRange.count,
            newStart: newRange.start,
            newCount: newRange.count,
            header: headerContext.isEmpty ? nil : headerContext
        )
    }

    private static func parseRange(_ part: Substring) -> LineRange? {
        let components = part.dropFirst().split(separator: ",")
        guard let startRaw = components.first else {
            return nil
        }

        return LineRange(
            start: Int(startRaw) ?? 0,
            count: components.count > 1 ? (Int(components[1]) ?? 1) : 1
        )
    }

    private static func parseHunkLines(
        lines: [String],
        index: inout Int,
        oldLineNumber: Int,
        newLineNumber: Int
    ) -> [DiffLine] {
        var diffLines: [DiffLine] = []
        var oldLineNumber = oldLineNumber
        var newLineNumber = newLineNumber

        while index < lines.count {
            let line = lines[index]
            if isHunkBoundary(line) {
                break
            }

            switch parseDiffLine(line, oldLineNumber: &oldLineNumber, newLineNumber: &newLineNumber) {
            case .line(let diffLine):
                diffLines.append(diffLine)
            case .skip:
                break
            case .end:
                return diffLines
            }

            index += 1
        }

        return diffLines
    }

    private static func isHunkBoundary(_ line: String) -> Bool {
        line.hasPrefix("diff --git ") || line.hasPrefix("@@")
    }

    private static func parseDiffLine(
        _ line: String,
        oldLineNumber: inout Int,
        newLineNumber: inout Int
    ) -> ParsedHunkLine {
        if line.hasPrefix("+") {
            defer { newLineNumber += 1 }
            return .line(
                DiffLine(
                    type: .added,
                    content: String(line.dropFirst()),
                    oldLineNumber: nil,
                    newLineNumber: newLineNumber
                )
            )
        }

        if line.hasPrefix("-") {
            defer { oldLineNumber += 1 }
            return .line(
                DiffLine(
                    type: .deleted,
                    content: String(line.dropFirst()),
                    oldLineNumber: oldLineNumber,
                    newLineNumber: nil
                )
            )
        }

        if line.hasPrefix(" ") {
            defer {
                oldLineNumber += 1
                newLineNumber += 1
            }
            return .line(
                DiffLine(
                    type: .context,
                    content: String(line.dropFirst()),
                    oldLineNumber: oldLineNumber,
                    newLineNumber: newLineNumber
                )
            )
        }

        if line.hasPrefix("\\") {
            // Skip "\ No newline at end of file" markers.
            return .skip
        }

        return .end
    }
}

private struct DiffFileBuilder {
    var oldPath: String?
    var newPath: String?
    var isBinary = false
    var isRenamed = false
    var hunks: [DiffHunk] = []

    init(headerLine: String) {
        if let headerPaths = Self.parseHeaderPaths(headerLine) {
            oldPath = headerPaths.oldPath
            newPath = headerPaths.newPath
        }
    }

    mutating func consumeMetadata(in lines: [String], index: inout Int) {
        while index < lines.count,
              !lines[index].hasPrefix("diff --git "),
              !lines[index].hasPrefix("--- "),
              !lines[index].hasPrefix("@@") {
            applyMetadataLine(lines[index])
            index += 1
        }
    }

    mutating func consumePathMarkers(in lines: [String], index: inout Int) {
        if index < lines.count, lines[index].hasPrefix("--- ") {
            oldPath = Self.parsePathMarker(lines[index], prefix: "--- ", expectedPathPrefix: "a/")
            index += 1
        }

        if index < lines.count, lines[index].hasPrefix("+++ ") {
            newPath = Self.parsePathMarker(lines[index], prefix: "+++ ", expectedPathPrefix: "b/")
            index += 1
        }
    }

    mutating func consumeHunks(in lines: [String], index: inout Int) {
        while index < lines.count, !lines[index].hasPrefix("diff --git ") {
            guard lines[index].hasPrefix("@@") else {
                index += 1
                continue
            }

            if let hunk = DiffParser.parseHunk(lines: lines, index: &index) {
                hunks.append(hunk)
            }
        }
    }

    func build() -> DiffFile {
        DiffFile(
            oldPath: oldPath,
            newPath: newPath,
            isBinary: isBinary,
            isRenamed: isRenamed,
            hunks: hunks
        )
    }

    mutating func applyMetadataLine(_ line: String) {
        if line.hasPrefix("Binary files") {
            isBinary = true
            return
        }

        if line.hasPrefix("rename from ") {
            isRenamed = true
            oldPath = String(line.dropFirst("rename from ".count))
            return
        }

        if line.hasPrefix("rename to ") {
            isRenamed = true
            newPath = String(line.dropFirst("rename to ".count))
            return
        }

        if line.hasPrefix("new file") {
            oldPath = nil
            return
        }

        if line.hasPrefix("deleted file") {
            newPath = nil
        }
    }

    private static func parseHeaderPaths(_ headerLine: String) -> HeaderPaths? {
        guard let aRange = headerLine.range(of: " a/"),
              let bRange = headerLine.range(of: " b/", range: aRange.upperBound..<headerLine.endIndex) else {
            return nil
        }

        return HeaderPaths(
            oldPath: String(headerLine[aRange.upperBound..<bRange.lowerBound]),
            newPath: String(headerLine[bRange.upperBound...])
        )
    }

    private static func parsePathMarker(_ line: String, prefix: String, expectedPathPrefix: String) -> String? {
        let pathLine = String(line.dropFirst(prefix.count))
        if pathLine == "/dev/null" {
            return nil
        }
        if pathLine.hasPrefix(expectedPathPrefix) {
            return String(pathLine.dropFirst(expectedPathPrefix.count))
        }
        return nil
    }
}

private struct HeaderPaths {
    let oldPath: String
    let newPath: String
}

private struct HunkHeader {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let header: String?
}

private struct LineRange {
    let start: Int
    let count: Int
}

private enum ParsedHunkLine {
    case line(DiffLine)
    case skip
    case end
}
