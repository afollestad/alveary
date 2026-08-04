@preconcurrency import AppKit
import Foundation
import SwiftUI

/// A fenced diff drawn with the Changes tab's columns: old line number, new line number, marker,
/// a hairline, then the code.
///
/// Only the code goes in the text view, so the gutter cannot be selected or copied and the block
/// still yields plain source. Everything left of the hairline is drawn here, aligned to the text
/// view's own line fragments — the content never wraps, so one fragment is one row.
@MainActor
final class AppKitDiffCodeBlockView: NSView {
    var onHeightInvalidated: (() -> Void)?

    private var rows: [DiffCodeHighlighting.Row] = []
    private var font: NSFont = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    private var metrics = AppKitDiffCodeBlockMetrics.empty
    private var textView: AppKitMarkdownTextView?
    // Text layout is the expensive part and the transcript redraws on every scroll, so the line
    // geometry is measured once per content change; row rects are cheap arithmetic over it.
    private var cachedLines: [LineGeometry]?

    /// One laid-out line: where it sits, and how far its glyphs actually reach.
    fileprivate struct LineGeometry {
        let minY: CGFloat
        let height: CGFloat
        let contentWidth: CGFloat
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        let textSize = contentTextSize()
        return NSSize(
            width: ceil(metrics.contentLeading + textSize.width + AppKitDiffCodeBlockMetrics.contentTrailingPadding),
            height: ceil(textSize.height + AppKitDiffCodeBlockMetrics.verticalPadding * 2)
        )
    }

    func configure(rows: [DiffCodeHighlighting.Row], font: NSFont) {
        guard self.rows != rows || self.font != font else {
            return
        }
        self.rows = rows
        self.font = font
        metrics = AppKitDiffCodeBlockMetrics(rows: rows, font: font)
        invalidateCaches()
        rebuildTextView()
        needsDisplay = true
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    override func layout() {
        super.layout()
        let textSize = contentTextSize()
        textView?.frame = NSRect(
            x: metrics.contentLeading,
            y: AppKitDiffCodeBlockMetrics.verticalPadding,
            width: max(textSize.width, bounds.width - metrics.contentLeading),
            height: ceil(textSize.height)
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (index, frame) in rowFrames().enumerated() where index < rows.count {
            guard frame.intersects(dirtyRect) else {
                continue
            }
            AppKitDiffGutterPainter.draw(row: rows[index], in: frame, metrics: metrics, font: font)
        }
        drawSeparator(in: dirtyRect)
    }
}

private extension AppKitDiffCodeBlockView {
    func rebuildTextView() {
        textView?.removeFromSuperview()
        let textView = AppKitMarkdownTextView(
            content: AppKitDiffCodeBlockContent.attributedString(rows: rows, font: font),
            wrapsToContainerWidth: false,
            heightInvalidationHandler: { [weak self] in
                self?.invalidateCaches()
                self?.invalidateIntrinsicContentSize()
                self?.onHeightInvalidated?()
            }
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(textView)
        self.textView = textView
    }

    func invalidateCaches() {
        cachedLines = nil
    }

    func contentTextSize() -> NSSize {
        let lines = lineGeometry()
        return NSSize(
            width: ceil(lines.map(\.contentWidth).max() ?? 0),
            height: ceil(lines.last.map { $0.minY + $0.height } ?? 0)
        )
    }

    /// One rect per row, spanning the view's full width at the height its line fragment occupies.
    func rowFrames() -> [NSRect] {
        let top = AppKitDiffCodeBlockMetrics.verticalPadding
        return lineGeometry().map { line in
            NSRect(x: 0, y: line.minY + top, width: bounds.width, height: line.height)
        }
    }

    /// The width comes from each fragment's *used* rect, never `usedRect(for:)`: an unbounded text
    /// container reports its own clamped width there, which would make the block scroll for miles.
    func lineGeometry() -> [LineGeometry] {
        if let cachedLines {
            return cachedLines
        }
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage,
              textStorage.length > 0 else {
            return []
        }
        layoutManager.ensureLayout(for: textContainer)
        var lines: [LineGeometry] = []
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { rect, usedRect, _, _, _ in
            lines.append(
                LineGeometry(minY: rect.origin.y, height: rect.height, contentWidth: usedRect.maxX)
            )
        }
        // A diff ending in an added blank line leaves the text ending in a newline, and the layout
        // manager parks that final empty line in its extra fragment, outside the enumeration above.
        if layoutManager.extraLineFragmentTextContainer === textContainer {
            let rect = layoutManager.extraLineFragmentRect
            lines.append(LineGeometry(minY: rect.origin.y, height: rect.height, contentWidth: 0))
        }
        cachedLines = lines
        return lines
    }

    func drawSeparator(in dirtyRect: NSRect) {
        let separator = NSRect(
            x: metrics.gutterWidth - AppKitDiffCodeBlockMetrics.separatorWidth,
            y: 0,
            width: AppKitDiffCodeBlockMetrics.separatorWidth,
            height: bounds.height
        )
        guard separator.intersects(dirtyRect) else {
            return
        }
        AppKitDiffGutterPainter.drawSeparator(in: bounds, metrics: metrics)
    }
}

/// The code beside the gutter, shared with `AppKitMarkdownLayoutMeasurer` so a measured block and
/// a drawn one lay out the same text.
enum AppKitDiffCodeBlockContent {
    static func attributedString(rows: [DiffCodeHighlighting.Row], font: NSFont) -> NSAttributedString {
        let attributed = NSMutableAttributedString()
        for (index, row) in rows.enumerated() {
            attributed.append(
                NSAttributedString(
                    string: row.text,
                    attributes: [
                        .font: font,
                        .foregroundColor: row.occupiesGutter ? NSColor.labelColor : NSColor.secondaryLabelColor
                    ]
                )
            )
            if index < rows.count - 1 {
                attributed.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            }
        }
        return attributed
    }
}

/// The gutter's column widths, shared with `AppKitMarkdownLayoutMeasurer` so a measured diff block
/// and a drawn one cannot disagree about where the code starts.
struct AppKitDiffCodeBlockMetrics: Equatable {
    static let verticalPadding: CGFloat = 10
    static let contentLeadingPadding: CGFloat = 10
    static let contentTrailingPadding: CGFloat = 12
    static let separatorWidth: CGFloat = 1

    static let empty = AppKitDiffCodeBlockMetrics(rows: [], font: .monospacedSystemFont(ofSize: 11, weight: .regular))

    let showsLineNumbers: Bool
    let numberColumnWidth: CGFloat
    let markerColumnWidth: CGFloat

    var gutterWidth: CGFloat {
        (showsLineNumbers ? numberColumnWidth * 2 : 0) + markerColumnWidth
    }

    var contentLeading: CGFloat {
        gutterWidth + Self.contentLeadingPadding
    }

    init(rows: [DiffCodeHighlighting.Row], font: NSFont) {
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        let digits = rows.reduce(1) { widest, row in
            max(widest, [row.oldNumber, row.newNumber].compactMap { $0 }.map { String($0).count }.max() ?? 1)
        }
        showsLineNumbers = DiffCodeHighlighting.showsLineNumbers(in: rows)
        numberColumnWidth = ceil(CGFloat(digits) * digitWidth) + 12
        markerColumnWidth = ceil(digitWidth) + 12
    }

    func oldNumberColumn(in frame: NSRect) -> NSRect {
        NSRect(x: 0, y: frame.origin.y, width: numberColumnWidth - 4, height: frame.height)
    }

    func newNumberColumn(in frame: NSRect) -> NSRect {
        NSRect(x: numberColumnWidth, y: frame.origin.y, width: numberColumnWidth - 4, height: frame.height)
    }

    func markerColumn(in frame: NSRect) -> NSRect {
        NSRect(
            x: gutterWidth - markerColumnWidth,
            y: frame.origin.y,
            width: markerColumnWidth - 6,
            height: frame.height
        )
    }
}

/// The diff washes as `NSColor`, taken from the Changes tab's own `DiffLine.LineType` tokens so the
/// two surfaces cannot drift.
/// Every swatch is a cached dynamic `NSColor` that resolves per appearance at draw time. Drawing
/// asks for two of them per row on every redraw, and the transcript redraws on scroll, so building
/// them from their SwiftUI tokens per call would allocate through the whole visible diff each frame.
enum AppKitDiffCodeBlockPalette {
    static func rowWash(for kind: DiffCodeHighlighting.LineKind) -> NSColor? {
        switch kind {
        case .added:
            addedRowWash
        case .deleted:
            deletedRowWash
        case .hunkHeader:
            hunkHeaderWash
        case .fileHeader, .context:
            nil
        }
    }

    static func gutterWash(for kind: DiffCodeHighlighting.LineKind) -> NSColor {
        switch kind {
        case .added:
            addedGutterWash
        case .deleted:
            deletedGutterWash
        case .fileHeader, .hunkHeader, .context:
            contextGutterWash
        }
    }

    static func markerColor(for kind: DiffCodeHighlighting.LineKind) -> NSColor {
        switch kind {
        case .added:
            addedMarker
        case .deleted:
            deletedMarker
        case .fileHeader, .hunkHeader, .context:
            .secondaryLabelColor
        }
    }

    static let separator = NSColor(Color.primary.opacity(0.06))

    private static let addedRowWash = NSColor(DiffLine.LineType.added.diffLineRowWash)
    private static let deletedRowWash = NSColor(DiffLine.LineType.deleted.diffLineRowWash)
    private static let hunkHeaderWash = NSColor(Color.primary.opacity(0.06))
    private static let addedGutterWash = NSColor(DiffLine.LineType.added.diffGutterWash)
    private static let deletedGutterWash = NSColor(DiffLine.LineType.deleted.diffGutterWash)
    private static let contextGutterWash = NSColor(DiffLine.LineType.context.diffGutterWash)
    private static let addedMarker = NSColor(Color.green)
    private static let deletedMarker = NSColor(Color.red)
}
