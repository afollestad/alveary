import AppKit

enum AppKitChatComposerTopContentSeverity {
    case warning
    case error
    case info
}

/// Native owner for the composer content that sits above the editor.
///
/// The production AppKit composer panel uses this view for last-turn errors,
/// session-continuity notices, and staged-context banners so those rows measure
/// and hit-test in the same coordinate space as the editor and action row.
@MainActor
final class AppKitChatComposerTopContentView: NSView {
    struct Configuration {
        var items: [Item]

        static var empty: Configuration {
            Configuration(items: [])
        }
    }

    enum Item {
        case inlineBanner(InlineBannerConfiguration)
        case stagedContext(StagedContextConfiguration)
    }

    struct InlineBannerConfiguration {
        let message: String
        let severity: AppKitChatComposerTopContentSeverity
        let actionTitle: String?
        let onAction: (() -> Void)?
        let onDismiss: (() -> Void)?
    }

    struct StagedContextConfiguration {
        let context: String
        let onDismiss: () -> Void
    }

    private var itemViews: [AppKitChatComposerTopContentItemView] = []

    var hasContent: Bool {
        !itemViews.isEmpty
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(for: bounds.width))
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(for: bounds.width))
    }

    func configure(_ configuration: Configuration) {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = configuration.items.map { item in
            let view = AppKitChatComposerTopContentItemView()
            view.configure(item)
            addSubview(view)
            return view
        }
        isHidden = itemViews.isEmpty
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var currentY: CGFloat = 0
        for (index, itemView) in itemViews.enumerated() {
            if index > 0 {
                currentY += Self.itemSpacing
            }
            let height = itemView.measuredHeight(for: bounds.width)
            itemView.frame = NSRect(x: 0, y: currentY, width: bounds.width, height: height)
            currentY += height
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        itemViews.forEach { $0.updateAppearance() }
    }

    private func measuredHeight(for width: CGFloat) -> CGFloat {
        guard !itemViews.isEmpty else {
            return 0
        }
        let itemHeight = itemViews.reduce(CGFloat(0)) { partial, itemView in
            partial + itemView.measuredHeight(for: width)
        }
        return ceil(itemHeight + CGFloat(max(itemViews.count - 1, 0)) * Self.itemSpacing)
    }

    private static let itemSpacing: CGFloat = 8
}

private final class AppKitChatComposerTopContentItemView: NSView {
    private enum Content {
        case inlineBanner(AppKitChatComposerTopContentView.InlineBannerConfiguration)
        case stagedContext(AppKitChatComposerTopContentView.StagedContextConfiguration)
    }

    private let backgroundView = AppKitFlippedDynamicColorView()
    private let iconView = AppKitDynamicTintImageView()
    private let messageField = NSTextField(labelWithString: "")
    private let actionButton = ComposerTopContentButton(style: .secondary)
    private let dismissButton = ComposerTopContentButton(style: .icon(symbolName: "xmark"))

    private var content: Content?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ item: AppKitChatComposerTopContentView.Item) {
        switch item {
        case .inlineBanner(let configuration):
            content = .inlineBanner(configuration)
            messageField.stringValue = configuration.message
            messageField.font = NSFont.preferredFont(forTextStyle: .subheadline)
            messageField.lineBreakMode = .byWordWrapping
            messageField.maximumNumberOfLines = 0
            actionButton.configure(title: configuration.actionTitle ?? "", isEnabled: configuration.actionTitle != nil)
            actionButton.actionHandler = configuration.onAction
            actionButton.isHidden = configuration.actionTitle == nil || configuration.onAction == nil
            dismissButton.actionHandler = configuration.onDismiss
            dismissButton.isHidden = configuration.onDismiss == nil
            dismissButton.setAccessibilityLabel("Dismiss banner")
            iconView.image = symbolImage(named: configuration.severity.symbolName, pointSize: 15, weight: .semibold)
        case .stagedContext(let configuration):
            content = .stagedContext(configuration)
            messageField.stringValue = Self.summary(for: configuration.context)
            messageField.font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .medium)
            messageField.lineBreakMode = .byTruncatingTail
            messageField.maximumNumberOfLines = 1
            actionButton.isHidden = true
            actionButton.actionHandler = nil
            dismissButton.isHidden = false
            dismissButton.actionHandler = configuration.onDismiss
            dismissButton.setAccessibilityLabel("Dismiss context")
            iconView.image = symbolImage(named: "paperclip", pointSize: 14, weight: .medium)
        }
        messageField.setAccessibilityLabel(messageField.stringValue)
        updateAppearance()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func measuredHeight(for width: CGFloat) -> CGFloat {
        let availableWidth = max(width, 0)
        let textWidth = max(availableWidth - reservedHorizontalWidth, 0)
        let textHeight = measuredTextHeight(for: textWidth)
        return ceil((Self.verticalPadding * 2) + max(Self.iconSize, Self.buttonHeight, textHeight))
    }

    override func layout() {
        super.layout()
        backgroundView.frame = bounds

        let contentHeight = bounds.height - Self.verticalPadding * 2
        iconView.frame = NSRect(
            x: Self.horizontalPadding,
            y: Self.verticalPadding + max((contentHeight - Self.iconSize) / 2, 0),
            width: Self.iconSize,
            height: Self.iconSize
        )

        let dismissWidth = dismissButton.isHidden ? 0 : Self.iconButtonWidth
        let actionWidth = actionButton.isHidden ? 0 : actionButton.intrinsicContentSize.width
        let actionSpacing = actionButton.isHidden ? 0 : Self.trailingControlSpacing
        let dismissSpacing = dismissButton.isHidden ? 0 : Self.trailingControlSpacing

        if !dismissButton.isHidden {
            dismissButton.frame = NSRect(
                x: bounds.maxX - Self.horizontalPadding - dismissWidth,
                y: Self.verticalPadding + max((contentHeight - Self.buttonHeight) / 2, 0),
                width: dismissWidth,
                height: Self.buttonHeight
            )
        }

        if !actionButton.isHidden {
            let trailingAfterAction = Self.horizontalPadding + dismissWidth + dismissSpacing
            actionButton.frame = NSRect(
                x: bounds.maxX - trailingAfterAction - actionWidth,
                y: Self.verticalPadding + max((contentHeight - Self.buttonHeight) / 2, 0),
                width: actionWidth,
                height: Self.buttonHeight
            )
        }

        let textX = iconView.frame.maxX + Self.iconTextSpacing
        let trailing = Self.horizontalPadding + dismissWidth + dismissSpacing + actionWidth + actionSpacing
        let textWidth = max(bounds.width - textX - trailing, 0)
        let textHeight = measuredTextHeight(for: textWidth)
        messageField.frame = NSRect(
            x: textX,
            y: Self.verticalPadding + max((contentHeight - textHeight) / 2, 0),
            width: textWidth,
            height: textHeight
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateAppearance() {
        guard let content else {
            return
        }

        switch content {
        case .inlineBanner(let configuration):
            let accentColor = configuration.severity.accentColor
            backgroundView.setLayerFillColor(accentColor, alpha: 0.12)
            backgroundView.setLayerStrokeColor(accentColor, alpha: 0.3)
            backgroundView.layer?.borderWidth = 1
            iconView.setDynamicContentTintColor(accentColor)
            messageField.textColor = .labelColor
        case .stagedContext:
            backgroundView.setLayerFillColorPreservingResolvedAlpha { appearance in
                let resolved = NSColor.secondaryLabelColor.resolved(for: appearance)
                return resolved.withAlphaComponent(resolved.alphaComponent * 0.08)
            }
            backgroundView.setLayerStrokeColor(nil)
            backgroundView.layer?.borderWidth = 0
            iconView.setDynamicContentTintColor(.secondaryLabelColor)
            messageField.textColor = .secondaryLabelColor
        }
        actionButton.needsDisplay = true
        dismissButton.needsDisplay = true
    }

    private func setup() {
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = Self.cornerRadius
        addSubview(backgroundView)

        iconView.setAccessibilityElement(false)
        backgroundView.addSubview(iconView)

        messageField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        backgroundView.addSubview(messageField)

        actionButton.isHidden = true
        backgroundView.addSubview(actionButton)

        dismissButton.isHidden = true
        dismissButton.setAccessibilityLabel("Dismiss")
        backgroundView.addSubview(dismissButton)
    }

    private var reservedHorizontalWidth: CGFloat {
        let dismissWidth = dismissButton.isHidden ? 0 : Self.iconButtonWidth + Self.trailingControlSpacing
        let actionWidth = actionButton.isHidden ? 0 : actionButton.intrinsicContentSize.width + Self.trailingControlSpacing
        return Self.horizontalPadding * 2 + Self.iconSize + Self.iconTextSpacing + actionWidth + dismissWidth
    }

    private func measuredTextHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return messageField.fittingSize.height
        }
        let rect = messageField.attributedStringValue.boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
    }

    private func symbolImage(named name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private static func summary(for context: String) -> String {
        let firstLine = context
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Context included."

        if firstLine.count > 96 {
            return String(firstLine.prefix(93)) + "..."
        }
        return firstLine
    }

    private static let cornerRadius: CGFloat = 14
    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 10
    private static let iconSize: CGFloat = 16
    private static let iconTextSpacing: CGFloat = 12
    private static let trailingControlSpacing: CGFloat = 8
    private static let iconButtonWidth: CGFloat = 22
    private static let buttonHeight: CGFloat = 22
}

extension AppKitChatComposerTopContentSeverity {
    var symbolName: String {
        switch self {
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        case .info:
            return .systemBlue
        }
    }
}
