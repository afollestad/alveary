@preconcurrency import AppKit
import Foundation

/// The icon-and-title row above an AppKit alert's body.
///
/// The glyph is an `AppKitDynamicTintImageView`, not a text attachment inside the body's own
/// attributed string. An attachment would have to bake the accent into its bitmap, and
/// `AppKitMarkdownView` rebuilds on content changes rather than on effective-appearance changes, so
/// a light/dark switch would strand the icon in the previous scheme's color. The title is an
/// `NSTextField` for the same reason the list markers are: a dynamic `textColor` resolves itself.
///
/// `AppKitMarkdownLayoutMeasurer` predicts this row without building it, so `height(font:)` and
/// `naturalWidth(kind:font:)` are the single source for its geometry — the row is pinned to those
/// numbers rather than left to Auto Layout's own idea of the label's height.
@MainActor
final class AppKitMarkdownAlertHeaderView: NSView {
    private let font: NSFont

    init(kind: AppMarkdownAlertKind, font: NSFont) {
        self.font = font
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [Self.iconView(kind: kind, font: font), Self.titleLabel(kind: kind, font: font)])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = AppMarkdownAlertMetrics.iconSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setAccessibilityRole(.staticText)
        setAccessibilityLabel(kind.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height(font: font))
    }

    /// The row's height, and the measurer's. Taken from the body font's line height rather than the
    /// label's own intrinsic size so the two cannot drift; the glyph raises it only if a symbol ever
    /// renders taller than the text it labels.
    static func height(font: NSFont) -> CGFloat {
        ceil(max(font.ascender - font.descender + font.leading, symbolPointSize(font: font)))
    }

    static func naturalWidth(kind: AppMarkdownAlertKind, font: NSFont) -> CGFloat {
        let iconWidth = iconImage(kind: kind, font: font)?.size.width ?? symbolPointSize(font: font)
        let titleWidth = (kind.title as NSString)
            .size(withAttributes: [NSAttributedString.Key.font: titleFont(font: font)])
            .width
        return ceil(iconWidth + AppMarkdownAlertMetrics.iconSpacing + titleWidth)
    }

    private static func iconView(kind: AppMarkdownAlertKind, font: NSFont) -> NSView {
        let imageView = AppKitDynamicTintImageView()
        imageView.image = iconImage(kind: kind, font: font)
        imageView.imageScaling = .scaleNone
        imageView.setDynamicContentTintColor(kind.accentNSColor)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        // The title beside it already names the alert; two elements would read it twice.
        imageView.setAccessibilityElement(false)
        return imageView
    }

    private static func titleLabel(kind: AppMarkdownAlertKind, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: kind.title)
        label.font = titleFont(font: font)
        label.textColor = kind.accentNSColor
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)
        return label
    }

    private static func iconImage(kind: AppMarkdownAlertKind, font: NSFont) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolPointSize(font: font), weight: .semibold)
        let image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private static func titleFont(font: NSFont) -> NSFont {
        NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
    }

    private static func symbolPointSize(font: NSFont) -> CGFloat {
        font.pointSize
    }
}
