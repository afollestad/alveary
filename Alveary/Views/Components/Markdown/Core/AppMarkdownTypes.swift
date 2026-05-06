import Foundation

let markdownInlineCodeFontScale: CGFloat = 0.94
let markdownTableCornerRadius: CGFloat = 12

/// Returns code text as it should be displayed in transcript/code surfaces.
/// Markdown and tool output can include trailing blank lines that SwiftUI and AppKit
/// measure differently, so all renderers trim the blank tail from the same place.
func appMarkdownCodeDisplayContent(_ content: String) -> String {
    content.trimmingTrailingBlankLines()
}

enum AppMarkdownInlineCodeStyle: Hashable, Sendable {
    case standard
    case userBubble
    /// Accent-derived palette used by composer surfaces. The live input field draws
    /// chips directly from `AppMarkdownCodeBlockPalette.composerChip*`, and queue
    /// items render through this style so they match composer chrome.
    case composer
}

private extension String {
    func trimmingTrailingBlankLines() -> String {
        let lineRanges = indicesOfLines
        guard let lastContentLine = lineRanges.last(where: { lineRange in
            self[lineRange].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }) else {
            return ""
        }
        let suffix = self[lastContentLine.upperBound...]
        if suffix.contains(where: \.isNewline) {
            return String(self[..<lastContentLine.upperBound])
        }
        return self
    }

    private var indicesOfLines: [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var lineStart = startIndex
        var cursor = startIndex
        while cursor < endIndex {
            if self[cursor].isNewline {
                ranges.append(lineStart..<cursor)
                lineStart = index(after: cursor)
            }
            cursor = index(after: cursor)
        }
        ranges.append(lineStart..<endIndex)
        return ranges
    }
}

enum AppMarkdownComposerChipMode: Sendable {
    case none
    case composer
}

struct AppMarkdownDocument: Equatable, Sendable {
    let content: AttributedString
    let taskStateNamespace: String

    init(
        content: AttributedString,
        taskStateNamespace: String = ""
    ) {
        self.content = content
        self.taskStateNamespace = taskStateNamespace
    }
}

struct AppMarkdownTaskListState {
    let isChecked: Bool
    let contentWithoutMarker: AttributedString

    init?(content: AttributedString) {
        var content = content
        let text = String(content.characters)
        let markerLength: Int
        if text.hasPrefix("[ ] ") {
            isChecked = false
            markerLength = 4
        } else if text.hasPrefix("[ ]") {
            isChecked = false
            markerLength = 3
        } else if text.lowercased().hasPrefix("[x] ") {
            isChecked = true
            markerLength = 4
        } else if text.lowercased().hasPrefix("[x]") {
            isChecked = true
            markerLength = 3
        } else {
            return nil
        }

        let markerEnd = content.characters.index(content.startIndex, offsetBy: markerLength)
        content.removeSubrange(content.startIndex..<markerEnd)
        contentWithoutMarker = content
    }
}

enum AppMarkdownTaskCheckboxStore {
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1_000
        return cache
    }()

    static func value(
        for id: String,
        defaultValue: Bool
    ) -> Bool {
        cache.object(forKey: id as NSString)?.boolValue ?? defaultValue
    }

    static func set(
        _ value: Bool,
        for id: String
    ) {
        cache.setObject(NSNumber(value: value), forKey: id as NSString)
    }
}
