@preconcurrency import AppKit
import Foundation

/// Alert-header geometry, shared by both renderers and by `AppKitMarkdownLayoutMeasurer`.
///
/// Like `AppMarkdownDetailsMetrics`, it lives in Core because the measurer predicts the AppKit
/// view's height without building it; a number spelled separately in the two would drift and leave
/// the transcript reserving height no drawn pixel occupies.
enum AppMarkdownAlertMetrics {
    /// Gap between the header glyph and its label. The glyph itself is sized from the surrounding
    /// body font in both renderers rather than pinned here, so a transcript running settings-backed
    /// typography scales the icon with the text it labels.
    static let iconSpacing: CGFloat = 6
    /// Gap between the header row and the alert body. Deliberately equal to
    /// `AppKitMarkdownMetrics.blockSpacing` and the SwiftUI block-stack spacing, so the header is
    /// just another block in the quote's child stack and the measurer adds a single term.
    static let headerSpacing: CGFloat = 8
}

/// One of GitHub's five alert blockquotes — `> [!WARNING]` and friends.
///
/// SF Symbols rather than the vendored Primer octicons: the AppKit renderer needs an `NSImage` for
/// its header attachment, and only two of the five glyphs are vendored today.
enum AppMarkdownAlertKind: String, CaseIterable, Sendable {
    case note
    case tip
    case important
    case warning
    case caution

    var title: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .caution: return "Caution"
        }
    }

    var symbolName: String {
        switch self {
        case .note: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .important: return "exclamationmark.bubble.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "exclamationmark.octagon.fill"
        }
    }

    /// Tints the quote bar, the header glyph, and the header label. The body stays at label color,
    /// and nothing behind an alert is filled — GitHub's alerts carry no background.
    var accentNSColor: NSColor {
        AppMarkdownAlertPalette.accentNSColor(for: self)
    }
}

/// A blockquote that opens with an alert marker, with the marker removed.
///
/// Detection runs on *parsed* content rather than markdown source, the way
/// `AppMarkdownTaskListState` does, because both renderers already hold the blockquote's
/// `AttributedString` and neither wants a second parse. That costs one point of GitHub fidelity:
/// Foundation renders a soft line break as a plain space, so `> [!NOTE]` alone on its line and
/// `> [!NOTE] inline text` are indistinguishable here, and this accepts both where GitHub accepts
/// only the first.
///
/// Stripping a prefix leaves every surviving run's presentation intent intact, which is what lets
/// callers keep passing the blockquote intent as `parent` when they render the remainder.
struct AppMarkdownAlert {
    let kind: AppMarkdownAlertKind
    let contentWithoutMarker: AttributedString

    init?(content: AttributedString) {
        // Both renderers construct one of these per blockquote per render pass, so the two-character
        // reject comes before the `String` copy that the rest of the parse needs.
        guard content.characters.starts(with: "[!") else {
            return nil
        }
        let text = String(content.characters)
        guard let markerEnd = text.firstIndex(of: "]") else {
            return nil
        }
        let nameStart = text.index(text.startIndex, offsetBy: 2)
        guard nameStart <= markerEnd,
              let kind = AppMarkdownAlertKind(rawValue: text[nameStart..<markerEnd].lowercased()) else {
            return nil
        }

        // The marker has to end the token: `[!NOTE]x` is prose that happens to start with brackets.
        // Whichever separator follows is consumed with it — a space when the source used a soft
        // line break, a newline when the pull request sanitizer turned that into a hard one.
        var cursor = text.index(after: markerEnd)
        let separatorStart = cursor
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        guard cursor > separatorStart || cursor == text.endIndex else {
            return nil
        }

        self.kind = kind
        var stripped = content
        let markerEndIndex = stripped.characters.index(
            stripped.startIndex,
            offsetBy: text.distance(from: text.startIndex, to: cursor)
        )
        stripped.removeSubrange(stripped.startIndex..<markerEndIndex)
        contentWithoutMarker = stripped
    }

    /// Whether anything follows the marker. All three render paths — both renderers and the
    /// measurer — branch on this so a bare `> [!NOTE]` costs its header and nothing else; spending
    /// `headerSpacing` on an absent body is what would leave a gap under it.
    var hasBody: Bool {
        contentWithoutMarker.characters.contains { !$0.isWhitespace }
    }
}
