import AppKit

/// Packs the existing native actions in reading order, wrapping whole controls before the shell
/// measures its height. This avoids an uncompressible horizontal stack in narrow transcripts.
@MainActor
final class AppKitReviewTeamRunActionsView: NSView {
    private let buttons: [NSButton]
    private let fullTitles: [String]
    private let originalTooltips: [String?]
    private let compactTitles: [String: String]
    private let fullWidth: CGFloat
    private var layoutWidth: CGFloat = 0

    init(buttons: [NSButton], compactTitles: [String: String]) {
        self.buttons = buttons
        self.fullTitles = buttons.map(\.title)
        self.originalTooltips = buttons.map(\.toolTip)
        self.compactTitles = compactTitles
        self.fullWidth = buttons.reduce(0) { $0 + $1.fittingSize.width } + CGFloat(max(0, buttons.count - 1)) * 8
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for button in buttons {
            button.translatesAutoresizingMaskIntoConstraints = true
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    var naturalWidth: CGFloat {
        fullWidth
    }

    override var fittingSize: NSSize {
        NSSize(width: naturalWidth, height: buttonFrames.map(\.maxY).max() ?? 0)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fittingSize.height)
    }

    func prepareLayout(width: CGFloat) {
        guard layoutWidth != width else { return }
        layoutWidth = width
        // Keep natural width based on full titles, otherwise a narrow layout could never grow
        // back. Short labels retain the complete action in VoiceOver and hover help.
        for (index, button) in buttons.enumerated() {
            let title = fullTitles[index]
            button.title = title
            button.toolTip = originalTooltips[index]
            if width > 0, button.fittingSize.width > width, let compact = compactTitles[title] {
                button.title = compact
                button.toolTip = [title, originalTooltips[index]].compactMap { $0 }.joined(separator: ". ")
            }
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        for (button, frame) in zip(buttons, buttonFrames) {
            button.frame = frame
        }
    }

    private var buttonFrames: [NSRect] {
        let width = layoutWidth > 0 ? layoutWidth : naturalWidth
        var originX: CGFloat = 0
        var originY: CGFloat = 0
        var rowHeight: CGFloat = 0
        return buttons.map { button in
            var size = button.fittingSize
            // Shared controls draw into their bounds, but their default fitting height assumes
            // the standard font. Leave room for the transcript's larger configured typography.
            if let font = button.font {
                let titleHeight = (button.title as NSString).size(withAttributes: [.font: font]).height
                size.height = max(size.height, ceil(titleHeight) + 6)
            }
            if originX > 0, originX + size.width > width {
                originX = 0
                originY += rowHeight + 6
                rowHeight = 0
            }
            let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
            originX += size.width + 8
            rowHeight = max(rowHeight, size.height)
            return frame
        }
    }
}
