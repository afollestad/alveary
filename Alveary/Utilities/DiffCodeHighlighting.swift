import Foundation
import SwiftUI

/// Turns a fenced diff block into rows a renderer can draw with columns, so it reads like the pull
/// request pane's Changes tab instead of flat monospaced text.
///
/// `DiffParser` does the parsing wherever it can, which is what supplies line numbers. It only
/// recognizes a patch carrying `diff --git` headers, though, and a model quoting a diff in chat
/// almost never writes those — so a fragment falls back to classifying each line by the same
/// prefixes, and those rows carry no numbers rather than inventing a starting line.
enum DiffCodeHighlighting {
    enum LineKind: Equatable {
        case fileHeader
        case hunkHeader
        case added
        case deleted
        case context

        /// A parsed diff line's kind, for callers building rows from `DiffFile` rather than from
        /// fence text — the review-proposal card, whose preview is already parsed.
        init(_ type: DiffLine.LineType) {
            switch type {
            case .added:
                self = .added
            case .deleted:
                self = .deleted
            case .context:
                self = .context
            }
        }
    }

    /// Fence languages that name a diff outright.
    static let languageNames: Set<String> = ["diff", "patch", "udiff"]

    /// Whether a block renders as a diff. An unlabeled block still qualifies when it carries a
    /// hunk header, because chat models routinely quote patches into a bare fence; a block that
    /// names a language the highlighter knows keeps that language's own coloring.
    static func rendersAsDiff(language: String, isRecognizedLanguage: Bool, source: String) -> Bool {
        if languageNames.contains(language) {
            return true
        }
        guard !isRecognizedLanguage else {
            return false
        }
        let kinds = lineKinds(in: source)
        return kinds.contains(.hunkHeader) && kinds.contains { $0 == .added || $0 == .deleted }
    }

    /// One rendered line: the text a gutter-drawing renderer shows, plus the columns beside it.
    struct Row: Equatable {
        let kind: LineKind
        /// The line without its `+`/`-`/space marker, which becomes its own column. Header lines
        /// carry no marker and keep their text whole.
        let text: String
        let oldNumber: Int?
        let newNumber: Int?

        var marker: String {
            switch kind {
            case .added:
                "+"
            case .deleted:
                "-"
            case .fileHeader, .hunkHeader, .context:
                ""
            }
        }

        /// Header lines read across the whole row; only change and context lines sit in columns.
        var occupiesGutter: Bool {
            kind == .added || kind == .deleted || kind == .context
        }
    }

    /// `DiffParser` owns every well-formed patch, line numbers included. Only a fragment it
    /// cannot see — a chat-quoted diff with no `diff --git` header — falls back to the classifier,
    /// and that path shows no numbers rather than inventing a starting line.
    static func rows(in source: String) -> [Row] {
        parsedRows(in: source) ?? classifiedRows(in: source)
    }

    /// Whether the number columns are worth drawing. A hunk header abbreviated to `@@` — how a
    /// model usually quotes one — carries no ranges, so every number would be a guess.
    static func showsLineNumbers(in rows: [Row]) -> Bool {
        rows.contains { $0.oldNumber != nil || $0.newNumber != nil }
    }

    static func lineKinds(in source: String) -> [LineKind] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var kinds = lines.map(kind(for:))
        for index in kinds.indices where kinds[index] == .context {
            // A bare path on the line above a hunk header is how a model writes a file break when
            // it is not reproducing git's own `diff --git`/`+++` headers.
            guard index + 1 < kinds.count,
                  kinds[index + 1] == .hunkHeader,
                  isPathLike(lines[index]) else {
                continue
            }
            kinds[index] = .fileHeader
        }
        return kinds
    }

    static func highlighted(_ source: String, colorScheme: ColorScheme) -> AttributedString {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let kinds = lineKinds(in: source)
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            let kind = kinds[index]
            result.append(styled(line, kind: kind))
            if index < lines.count - 1 {
                // The newline stays untinted so a row's fill ends with its text rather than
                // trailing a stub into the next line.
                result.append(AttributedString("\n"))
            }
        }
        return result
    }
}

private extension DiffCodeHighlighting {
    static func parsedRows(in source: String) -> [Row]? {
        let files = DiffParser.parse(source)
        guard files.contains(where: { !$0.hunks.isEmpty }) else {
            return nil
        }
        return files.flatMap { file in
            [Row(kind: .fileHeader, text: header(for: file), oldNumber: nil, newNumber: nil)]
                + file.hunks.flatMap(rows(for:))
        }
    }

    static func rows(for hunk: DiffHunk) -> [Row] {
        [Row(kind: .hunkHeader, text: header(for: hunk), oldNumber: nil, newNumber: nil)]
            + hunk.lines.map { line in
                Row(
                    kind: LineKind(line.type),
                    text: line.content,
                    oldNumber: line.oldLineNumber,
                    newNumber: line.newLineNumber
                )
            }
    }

    static func classifiedRows(in source: String) -> [Row] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        return zip(lines, lineKinds(in: source)).map { line, kind in
            Row(kind: kind, text: content(of: line, kind: kind), oldNumber: nil, newNumber: nil)
        }
    }

    static func header(for file: DiffFile) -> String {
        guard file.isRenamed,
              let oldPath = file.oldPath,
              oldPath != file.path else {
            return file.path
        }
        return "\(oldPath) → \(file.path)"
    }

    static func header(for hunk: DiffHunk) -> String {
        let ranges = "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
        guard let context = hunk.header, !context.isEmpty else {
            return ranges
        }
        return "\(ranges) \(context)"
    }

    /// Strips the marker only when the line actually carries one; a model writing context lines
    /// without their leading space would otherwise lose its first character.
    static func content(of line: Substring, kind: LineKind) -> String {
        guard kind == .added || kind == .deleted || kind == .context,
              let first = line.first,
              first == "+" || first == "-" || first == " " else {
            return String(line)
        }
        return String(line.dropFirst())
    }

    static let fileHeaderPrefixes = [
        "diff --git ", "index ", "--- ", "+++ ", "old mode ", "new mode ",
        "new file mode", "deleted file mode", "similarity index ", "dissimilarity index ",
        "rename from ", "rename to ", "copy from ", "copy to ", "Binary files ", "GIT binary patch"
    ]

    static func kind(for line: Substring) -> LineKind {
        if line.hasPrefix("@@") {
            return .hunkHeader
        }
        // `+++`/`---` path markers have to be claimed here, ahead of the add/delete prefixes.
        if fileHeaderPrefixes.contains(where: line.hasPrefix) {
            return .fileHeader
        }
        if line.hasPrefix("+") {
            return .added
        }
        if line.hasPrefix("-") {
            return .deleted
        }
        return .context
    }

    /// Conservative on purpose: an ordinary sentence above a hunk header is prose the model wrote,
    /// and promoting it to a file header would style the wrong line.
    static func isPathLike(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty
            && trimmed == line
            && !trimmed.contains(" ")
            && (trimmed.contains("/") || trimmed.contains("."))
    }

    static func styled(_ line: Substring, kind: LineKind) -> AttributedString {
        var attributed = AttributedString(String(line))
        attributed.foregroundColor = foreground(for: kind)
        if let tint = rowTint(for: kind) {
            attributed.backgroundColor = tint
        }
        applyMarkerColor(to: &attributed, kind: kind)
        return attributed
    }

    /// Only the leading `+`/`-` takes the change color; the content stays primary, matching
    /// `DiffLineRow`'s marker column in the Changes tab.
    static func applyMarkerColor(to attributed: inout AttributedString, kind: LineKind) {
        guard let markerColor = markerColor(for: kind),
              let markerEnd = attributed.characters.index(
                  attributed.startIndex,
                  offsetBy: 1,
                  limitedBy: attributed.endIndex
              ),
              markerEnd != attributed.startIndex else {
            return
        }
        attributed[attributed.startIndex..<markerEnd].foregroundColor = markerColor
    }

    static func foreground(for kind: LineKind) -> Color {
        switch kind {
        case .fileHeader, .hunkHeader:
            .secondary
        case .added, .deleted, .context:
            .primary
        }
    }

    /// Added and deleted rows reuse the Changes tab's own washes so the two surfaces cannot drift.
    static func rowTint(for kind: LineKind) -> Color? {
        switch kind {
        case .added:
            DiffLine.LineType.added.diffLineRowWash
        case .deleted:
            DiffLine.LineType.deleted.diffLineRowWash
        case .hunkHeader:
            Color.primary.opacity(0.06)
        case .fileHeader, .context:
            nil
        }
    }

    static func markerColor(for kind: LineKind) -> Color? {
        switch kind {
        case .added:
            .green
        case .deleted:
            .red
        case .fileHeader, .hunkHeader, .context:
            nil
        }
    }
}
