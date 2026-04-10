# Part 1d: Diff Parser

Pure parsing utility for unified diff output. No external dependencies. Continues from Part 1c.

## Implementation Status

- [x] Diff parser models and parser utility

## Diff Parser

A lightweight parser for unified diff output (`git diff --no-color`). Pure data models and string parsing — no external dependencies.

### Data Models

```swift
struct DiffFile: Sendable {  // Skep/DiffParser/DiffFile.swift
    let oldPath: String?         // nil for new files
    let newPath: String?         // nil for deleted files
    let isBinary: Bool
    let isRenamed: Bool
    let hunks: [DiffHunk]

    /// Convenience: the display path (prefers newPath, falls back to oldPath).
    var path: String { newPath ?? oldPath ?? "(unknown)" }

    var linesAdded: Int { hunks.reduce(0) { $0 + $1.linesAdded } }
    var linesDeleted: Int { hunks.reduce(0) { $0 + $1.linesDeleted } }
}

struct DiffHunk: Sendable {  // Skep/DiffParser/DiffHunk.swift
    let oldStart: Int            // Line number in the old file
    let oldCount: Int            // Number of lines in the old file
    let newStart: Int            // Line number in the new file
    let newCount: Int            // Number of lines in the new file
    let header: String?          // Optional function/class context after @@
    let lines: [DiffLine]

    var linesAdded: Int { lines.count(where: { $0.type == .added }) }
    var linesDeleted: Int { lines.count(where: { $0.type == .deleted }) }
}

struct DiffLine: Sendable {  // Skep/DiffParser/DiffLine.swift
    let type: LineType
    let content: String          // The line content (without the +/-/space prefix)
    let oldLineNumber: Int?      // nil for added lines
    let newLineNumber: Int?      // nil for deleted lines

    enum LineType: Sendable {
        case context             // Unchanged line (space prefix)
        case added               // Added line (+ prefix)
        case deleted             // Deleted line (- prefix)
    }
}
```

### Parser

```swift
enum DiffParser {  // Skep/DiffParser/DiffParser.swift
    /// Parse the full output of `git diff --no-color` into structured models.
    /// Handles multiple files, binary markers, renames, and empty diffs.
    static func parse(_ diffOutput: String) -> [DiffFile] {
        var files: [DiffFile] = []
        let lines = diffOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0

        while i < lines.count {
            // Look for "diff --git a/path b/path" header
            guard lines[i].hasPrefix("diff --git ") else { i += 1; continue }

            var oldPath: String?
            var newPath: String?
            var isBinary = false
            var isRenamed = false
            var hunks: [DiffHunk] = []

            // Parse the diff header line for a best-effort initial path guess.
            // This can be wrong for paths with spaces; the authoritative paths come
            // from the "--- a/" and "+++ b/" lines below, which overwrite these.
            let headerParts = lines[i]
            if let aRange = headerParts.range(of: " a/"),
               let bRange = headerParts.range(of: " b/", range: aRange.upperBound..<headerParts.endIndex) {
                oldPath = String(headerParts[aRange.upperBound..<bRange.lowerBound])
                newPath = String(headerParts[bRange.upperBound...])
            }
            i += 1

            // Parse extended header lines (index, old mode, new mode, rename, binary).
            // The while condition already exits on "--- " and "@@", so the loop body
            // only sees extended headers like "index", "old mode", "new file", "rename", "Binary".
            while i < lines.count && !lines[i].hasPrefix("diff --git ")
                    && !lines[i].hasPrefix("--- ") && !lines[i].hasPrefix("@@") {
                let line = lines[i]
                if line.hasPrefix("Binary files") { isBinary = true }
                if line.hasPrefix("rename from ") {
                    isRenamed = true
                    oldPath = String(line.dropFirst("rename from ".count))
                }
                if line.hasPrefix("rename to ") {
                    isRenamed = true
                    newPath = String(line.dropFirst("rename to ".count))
                }
                if line.hasPrefix("new file") { oldPath = nil }
                if line.hasPrefix("deleted file") { newPath = nil }
                i += 1
            }

            // Parse "--- a/path" and "+++ b/path" lines (may be absent for binary/empty diffs)
            if i < lines.count && lines[i].hasPrefix("--- ") {
                let path = String(lines[i].dropFirst(4))
                if path == "/dev/null" { oldPath = nil }
                else if path.hasPrefix("a/") { oldPath = String(path.dropFirst(2)) }
                i += 1
            }
            if i < lines.count && lines[i].hasPrefix("+++ ") {
                let path = String(lines[i].dropFirst(4))
                if path == "/dev/null" { newPath = nil }
                else if path.hasPrefix("b/") { newPath = String(path.dropFirst(2)) }
                i += 1
            }

            // Parse hunks
            while i < lines.count && !lines[i].hasPrefix("diff --git ") {
                guard lines[i].hasPrefix("@@") else { i += 1; continue }
                if let hunk = parseHunk(lines: lines, index: &i) {
                    hunks.append(hunk)
                }
            }

            files.append(DiffFile(
                oldPath: oldPath, newPath: newPath,
                isBinary: isBinary, isRenamed: isRenamed, hunks: hunks
            ))
        }
        return files
    }

    /// Parse a single hunk starting at the @@ line. Advances `index` past all hunk lines.
    private static func parseHunk(lines: [String], index: inout Int) -> DiffHunk? {
        let headerLine = lines[index]
        // Parse "@@ -oldStart,oldCount +newStart,newCount @@ optional context"
        // Uses manual string parsing instead of regex — regex literals cause multi-minute
        // compilation times and are unnecessary for this well-structured format.
        //
        // IMPORTANT: Search for the closing "@@" as a two-character pair, not as
        // individual "@" characters. Hunk headers often contain "@" in the context
        // suffix (e.g. "@@ -1,3 +1,3 @@ @objc func foo()" or "@MainActor").
        // Collecting all "@" chars individually would misidentify the context "@"
        // as part of the closing delimiter.
        guard headerLine.hasPrefix("@@ ") else { index += 1; return nil }
        // Find the closing " @@" after the opening "@@ ". The space before @@ is
        // required by the unified diff format; searching for " @@" avoids matching
        // a bare "@" in the range string (e.g. "@@ -1 +1 @@" has no space issue,
        // but "@@ -1,3 +1,3 @@ @objc" does).
        let searchStart = headerLine.index(headerLine.startIndex, offsetBy: 3) // skip opening "@@ "
        guard let closingRange = headerLine.range(of: " @@", range: searchStart..<headerLine.endIndex) else {
            index += 1; return nil
        }
        // Range string is between the opening "@@ " and the closing " @@"
        let rangeStr = String(headerLine[searchStart..<closingRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let parts = rangeStr.split(separator: " ")
        guard parts.count == 2 else { index += 1; return nil }
        let oldComponents = parts[0].dropFirst().split(separator: ",")  // drop "-"
        guard let oldStartRaw = oldComponents.first else { index += 1; return nil }
        let oldStart = Int(oldStartRaw) ?? 0
        let oldCount = oldComponents.count > 1 ? (Int(oldComponents[1]) ?? 1) : 1
        let newComponents = parts[1].dropFirst().split(separator: ",")  // drop "+"
        guard let newStartRaw = newComponents.first else { index += 1; return nil }
        let newStart = Int(newStartRaw) ?? 0
        let newCount = newComponents.count > 1 ? (Int(newComponents[1]) ?? 1) : 1
        // Header context is everything after the closing " @@ " (space after @@)
        let afterClosing = closingRange.upperBound
        let headerContext: String
        if afterClosing < headerLine.endIndex {
            headerContext = String(headerLine[afterClosing...]).trimmingCharacters(in: .whitespaces)
        } else {
            headerContext = ""
        }
        let header = headerContext.isEmpty ? nil : headerContext
        index += 1

        var diffLines: [DiffLine] = []
        var oldLine = oldStart
        var newLine = newStart

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("diff --git ") || line.hasPrefix("@@") { break }

            if line.hasPrefix("+") {
                diffLines.append(DiffLine(type: .added, content: String(line.dropFirst()),
                                          oldLineNumber: nil, newLineNumber: newLine))
                newLine += 1
            } else if line.hasPrefix("-") {
                diffLines.append(DiffLine(type: .deleted, content: String(line.dropFirst()),
                                          oldLineNumber: oldLine, newLineNumber: nil))
                oldLine += 1
            } else if line.hasPrefix(" ") {
                // Context line (space prefix)
                diffLines.append(DiffLine(type: .context, content: String(line.dropFirst()),
                                          oldLineNumber: oldLine, newLineNumber: newLine))
                oldLine += 1
                newLine += 1
            } else if line.hasPrefix("\\") {
                // "\ No newline at end of file" — skip, don't count as a line
            } else {
                // Unknown prefix or empty line (artifact of trailing newline in split output) — end of hunk
                break
            }
            index += 1
        }

        return DiffHunk(oldStart: oldStart, oldCount: oldCount,
                        newStart: newStart, newCount: newCount,
                        header: header, lines: diffLines)
    }
}
```

### Example: Input → Output

**Input** (from `git diff --no-color`):
```
diff --git a/src/auth.swift b/src/auth.swift
index 1a2b3c4..5d6e7f8 100644
--- a/src/auth.swift
+++ b/src/auth.swift
@@ -10,7 +10,8 @@ func validateToken(_ token: Token) -> Bool {
     guard let expiry = token.expiry else {
         return false
     }
-    return expiry > Date()
+    let now = Date()
+    return expiry > now && !token.isRevoked
 }
 
 func refreshToken(_ token: Token) async throws -> Token {
diff --git a/src/auth.test.swift b/src/auth.test.swift
new file mode 100644
--- /dev/null
+++ b/src/auth.test.swift
@@ -0,0 +1,5 @@
+import XCTest
+
+final class AuthTests: XCTestCase {
+    func testValidateExpiredToken() { }
+}
```

**Output** (`DiffParser.parse(input)`):
```
[
  DiffFile(
    oldPath: "src/auth.swift",
    newPath: "src/auth.swift",
    isBinary: false, isRenamed: false,
    hunks: [
      DiffHunk(
        oldStart: 10, oldCount: 7, newStart: 10, newCount: 8,
        header: "func validateToken(_ token: Token) -> Bool {",
        lines: [
          DiffLine(.context, "    guard let expiry = token.expiry else {",  old: 10, new: 10),
          DiffLine(.context, "        return false",                        old: 11, new: 11),
          DiffLine(.context, "    }",                                       old: 12, new: 12),
          DiffLine(.deleted, "    return expiry > Date()",                  old: 13, new: nil),
          DiffLine(.added,   "    let now = Date()",                        old: nil, new: 13),
          DiffLine(.added,   "    return expiry > now && !token.isRevoked", old: nil, new: 14),
          DiffLine(.context, "}",                                           old: 14, new: 15),
          DiffLine(.context, "",                                            old: 15, new: 16),
          DiffLine(.context, "func refreshToken(_ token: Token) async throws -> Token {", old: 16, new: 17),
        ]
      )
    ]
  ),
  DiffFile(
    oldPath: nil,              // new file
    newPath: "src/auth.test.swift",
    isBinary: false, isRenamed: false,
    hunks: [
      DiffHunk(
        oldStart: 0, oldCount: 0, newStart: 1, newCount: 5,
        header: nil,
        lines: [
          DiffLine(.added, "import XCTest",                           old: nil, new: 1),
          DiffLine(.added, "",                                        old: nil, new: 2),
          DiffLine(.added, "final class AuthTests: XCTestCase {",     old: nil, new: 3),
          DiffLine(.added, "    func testValidateExpiredToken() { }", old: nil, new: 4),
          DiffLine(.added, "}",                                       old: nil, new: 5),
        ]
      )
    ]
  )
]
```

### Edge Cases Handled

- **New files**: `--- /dev/null` → `oldPath` is nil
- **Deleted files**: `+++ /dev/null` → `newPath` is nil
- **Binary files**: `Binary files ... differ` line → `isBinary = true`, no hunks
- **Renames**: `rename from` / `rename to` set authoritative `oldPath` / `newPath`, including rename-only diffs with no hunks
- **No newline at EOF**: `\ No newline at end of file` lines are skipped
- **Empty diffs**: files with headers but no hunks parse as empty `hunks` arrays
- **Multiple files**: the parser splits on `diff --git` boundaries

### What's NOT Handled (and Why)

- **Submodule changes**: rare in agent-generated diffs; shown as raw text if encountered
- **Combined diffs** (merge conflicts with `diff --cc`): the app uses `git diff`, not `git diff --cc`
- **Copy headers** (`copy from` / `copy to`): v1 does not surface copy metadata separately from ordinary diffs
- **Permission-only changes** (`old mode`/`new mode` without content): parsed as an empty-hunk file, which is correct

**Unit tests for DiffParser:** cover single file, multi-file, new/deleted/renamed/binary files, and empty input. Non-obvious:
- `\ No newline at end of file` marker is skipped without crashing or producing a DiffLine
- Hunk header with `@` in context (e.g. `@@ -1,3 +1,3 @@ @objc func foo()`) — must detect the closing `@@` pair correctly
- Hunk header with count omitted (e.g. `@@ -1 +1 @@`) — count defaults to 1
- Pure rename with no hunks still preserves both `oldPath` and `newPath`
- Rename headers with spaces in the file path update `oldPath` / `newPath` correctly
- Malformed hunk header is skipped safely instead of trapping on an empty range component
- Multi-hunk file: line numbers reset correctly per hunk (don't carry over from previous hunk)
- Permission-only change (`old mode` / `new mode` with no content diff) produces empty `hunks` array
- Trailing empty line from `split()` does not produce a spurious context line
