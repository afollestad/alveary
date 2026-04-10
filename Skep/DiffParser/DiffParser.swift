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

            var oldPath: String?
            var newPath: String?
            var isBinary = false
            var isRenamed = false
            var hunks: [DiffHunk] = []

            let headerLine = lines[index]
            if let aRange = headerLine.range(of: " a/"),
               let bRange = headerLine.range(of: " b/", range: aRange.upperBound..<headerLine.endIndex) {
                oldPath = String(headerLine[aRange.upperBound..<bRange.lowerBound])
                newPath = String(headerLine[bRange.upperBound...])
            }
            index += 1

            while index < lines.count,
                  !lines[index].hasPrefix("diff --git "),
                  !lines[index].hasPrefix("--- "),
                  !lines[index].hasPrefix("@@") {
                let line = lines[index]

                if line.hasPrefix("Binary files") {
                    isBinary = true
                }
                if line.hasPrefix("rename from ") {
                    isRenamed = true
                    oldPath = String(line.dropFirst("rename from ".count))
                }
                if line.hasPrefix("rename to ") {
                    isRenamed = true
                    newPath = String(line.dropFirst("rename to ".count))
                }
                if line.hasPrefix("new file") {
                    oldPath = nil
                }
                if line.hasPrefix("deleted file") {
                    newPath = nil
                }

                index += 1
            }

            if index < lines.count, lines[index].hasPrefix("--- ") {
                let pathLine = String(lines[index].dropFirst(4))
                if pathLine == "/dev/null" {
                    oldPath = nil
                } else if pathLine.hasPrefix("a/") {
                    oldPath = String(pathLine.dropFirst(2))
                }
                index += 1
            }

            if index < lines.count, lines[index].hasPrefix("+++ ") {
                let pathLine = String(lines[index].dropFirst(4))
                if pathLine == "/dev/null" {
                    newPath = nil
                } else if pathLine.hasPrefix("b/") {
                    newPath = String(pathLine.dropFirst(2))
                }
                index += 1
            }

            while index < lines.count, !lines[index].hasPrefix("diff --git ") {
                guard lines[index].hasPrefix("@@") else {
                    index += 1
                    continue
                }

                if let hunk = parseHunk(lines: lines, index: &index) {
                    hunks.append(hunk)
                }
            }

            files.append(
                DiffFile(
                    oldPath: oldPath,
                    newPath: newPath,
                    isBinary: isBinary,
                    isRenamed: isRenamed,
                    hunks: hunks
                )
            )
        }

        return files
    }

    private static func parseHunk(lines: [String], index: inout Int) -> DiffHunk? {
        let headerLine = lines[index]
        guard headerLine.hasPrefix("@@ ") else {
            index += 1
            return nil
        }

        let searchStart = headerLine.index(headerLine.startIndex, offsetBy: 3)
        guard let closingRange = headerLine.range(of: " @@", range: searchStart..<headerLine.endIndex) else {
            index += 1
            return nil
        }

        let rangeString = String(headerLine[searchStart..<closingRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let parts = rangeString.split(separator: " ")
        guard parts.count == 2 else {
            index += 1
            return nil
        }

        let oldComponents = parts[0].dropFirst().split(separator: ",")
        guard let oldStartRaw = oldComponents.first else {
            index += 1
            return nil
        }

        let newComponents = parts[1].dropFirst().split(separator: ",")
        guard let newStartRaw = newComponents.first else {
            index += 1
            return nil
        }

        let oldStart = Int(oldStartRaw) ?? 0
        let oldCount = oldComponents.count > 1 ? (Int(oldComponents[1]) ?? 1) : 1
        let newStart = Int(newStartRaw) ?? 0
        let newCount = newComponents.count > 1 ? (Int(newComponents[1]) ?? 1) : 1
        let headerContext = String(headerLine[closingRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let header = headerContext.isEmpty ? nil : headerContext
        index += 1

        var diffLines: [DiffLine] = []
        var oldLineNumber = oldStart
        var newLineNumber = newStart

        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("diff --git ") || line.hasPrefix("@@") {
                break
            }

            if line.hasPrefix("+") {
                diffLines.append(
                    DiffLine(
                        type: .added,
                        content: String(line.dropFirst()),
                        oldLineNumber: nil,
                        newLineNumber: newLineNumber
                    )
                )
                newLineNumber += 1
            } else if line.hasPrefix("-") {
                diffLines.append(
                    DiffLine(
                        type: .deleted,
                        content: String(line.dropFirst()),
                        oldLineNumber: oldLineNumber,
                        newLineNumber: nil
                    )
                )
                oldLineNumber += 1
            } else if line.hasPrefix(" ") {
                diffLines.append(
                    DiffLine(
                        type: .context,
                        content: String(line.dropFirst()),
                        oldLineNumber: oldLineNumber,
                        newLineNumber: newLineNumber
                    )
                )
                oldLineNumber += 1
                newLineNumber += 1
            } else if line.hasPrefix("\\") {
                // Skip "\ No newline at end of file" markers.
            } else {
                break
            }

            index += 1
        }

        return DiffHunk(
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            header: header,
            lines: diffLines
        )
    }
}
