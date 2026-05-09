@preconcurrency import AppKit

struct AppTextEditorInlineHint: Equatable {
    let text: String
}

enum AppTextEditorChipDisplayMode: Equatable {
    case fullText
    case compactLabel(String)
}

final class AppTextEditorInlineHintView: NSView {
    var text = "" {
        didSet {
            needsDisplay = true
        }
    }

    var font: NSFont = .preferredFont(forTextStyle: .body) {
        didSet {
            needsDisplay = true
        }
    }

    var textColor: NSColor = .placeholderTextColor {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        (text as NSString).draw(
            with: bounds.intersection(dirtyRect),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }
}
