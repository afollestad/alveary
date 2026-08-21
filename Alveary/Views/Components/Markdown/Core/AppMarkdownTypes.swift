import BlockInputKit
import Foundation

let markdownInlineCodeFontScale: CGFloat = 0.94
let markdownTableCornerRadius: CGFloat = AppCornerRadius.standard

/// Alpha for inline-code fills drawn behind already-muted text — tool-row summaries and the
/// transcript widget cards' secondary lines. The regular chip fills are tuned for body text and
/// overpower a `secondaryLabelColor` line.
let markdownMutedInlineCodeFillOpacity: CGFloat = 0.08

/// Returns code text as it should be displayed in transcript/code surfaces.
/// Markdown and tool output can include trailing blank lines that SwiftUI and AppKit
/// measure differently, so all renderers trim the blank tail from the same place.
func appMarkdownCodeDisplayContent(_ content: String) -> String {
    content.trimmingTrailingBlankLines()
}

enum AppMarkdownInlineCodeStyle: Hashable, Sendable {
    case standard
    /// Neutral palette tuned for assistant chat bubbles. It keeps the same dark-mode
    /// treatment as `.standard`, while using a stronger light-mode fill so inline code
    /// is distinct from the assistant bubble surface.
    case assistantBubble
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
    let blocks: [AppMarkdownDocumentBlock]

    init(
        content: AttributedString,
        taskStateNamespace: String = "",
        blocks: [AppMarkdownDocumentBlock]? = nil
    ) {
        self.content = content
        self.taskStateNamespace = taskStateNamespace
        self.blocks = blocks ?? [.markdown(content)]
    }
}

enum AppMarkdownDocumentBlock: Equatable, Sendable {
    case markdown(AttributedString)
    case image(AppMarkdownImageBlock)
    case details(AppMarkdownDetailsBlock)
}

struct AppMarkdownImageBlock: Equatable, Sendable {
    let image: BlockInputImage

    var accessibilityLabel: String {
        image.altText.isEmpty ? image.source : image.altText
    }
}

/// A GitHub `<details>` disclosure. Its body is `[AppMarkdownDocumentBlock]` rather than a
/// flat `AttributedString` so images — and nested `<details>` — inside a disclosure keep the
/// same block treatment they get at the top level; the array is also what gives the enum case
/// its indirection.
///
/// The expanded flag deliberately lives in `AppMarkdownDetailsExpansionStore`, not here: this
/// type is parsed once and shared across every row rendering the same markdown, so a stored
/// flag would toggle every copy at once.
struct AppMarkdownDetailsBlock: Equatable, Sendable {
    let summary: AttributedString
    let blocks: [AppMarkdownDocumentBlock]
    /// The `open` attribute. Only the *initial* state — once a reader toggles the disclosure,
    /// the store's value wins.
    let isInitiallyOpen: Bool
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

/// Which `<details>` disclosures a reader has opened, keyed the same way task checkboxes are:
/// document namespace plus source-order path. Both renderers place disclosures inside recycling
/// containers — the Changes tab's `LazyVStack`, the transcript's row list — which discard view
/// state when a row leaves the realized window, so a scrolled-away disclosure would silently
/// snap shut without this.
///
/// `generation` exists for the AppKit side: `AppKitMarkdownPreparedLayoutCache` answers from a
/// key that does not otherwise know a disclosure moved, and would keep serving the pre-toggle
/// height. Keying on the counter retires those entries.
enum AppMarkdownDetailsExpansionStore {
    /// Prefixed so a disclosure and a task checkbox occupying the same source-order path in the
    /// same document cannot land on one another's entry.
    static func key(namespace: String, path: String) -> String {
        "details:\(namespace):\(path)"
    }

    /// Locked rather than a bare `static var`: `AppKitMarkdownPreparedLayoutKey` reads this from
    /// its initializer's default argument, and that initializer is reachable from the transcript's
    /// async preparation path. A plain `nonisolated(unsafe)` counter would silence the compiler on
    /// exactly the call this needs it to check.
    static var generation: Int {
        generationState.withLock { $0 }
    }

    private static let generationState = LockedState(0)

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
        bumpGeneration()
    }

    /// Tests share one process, so a leaked entry from an earlier case would decide a later
    /// case's collapsed/expanded assertions.
    static func removeAll() {
        cache.removeAllObjects()
        bumpGeneration()
    }

    private static func bumpGeneration() {
        generationState.withLock { $0 &+= 1 }
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
