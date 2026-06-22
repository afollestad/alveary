import AgentCLIKit
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
        case goalStatus(GoalStatusConfiguration)
        case inlineBanner(InlineBannerConfiguration)
        case stagedContext(StagedContextConfiguration)
    }

    struct GoalStatusConfiguration {
        let snapshot: AgentGoalSnapshot
        let actionError: String?
        let onPause: (() -> Void)?
        let onResume: (() -> Void)?
        let onDelete: (() -> Void)?
        let onDismissTerminal: (() -> Void)?
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
        case goalStatus(AppKitChatComposerTopContentView.GoalStatusConfiguration)
        case inlineBanner(AppKitChatComposerTopContentView.InlineBannerConfiguration)
        case stagedContext(AppKitChatComposerTopContentView.StagedContextConfiguration)
    }

    private let backgroundView = AppKitFlippedDynamicColorView()
    private let iconView = AppKitDynamicTintImageView()
    private let messageField = NSTextField(labelWithString: "")
    private let objectiveField = NSTextField(labelWithString: "")
    private let metadataField = NSTextField(labelWithString: "")
    private let actionButton = ComposerTopContentButton(style: .secondary)
    private let pauseButton = ComposerTopContentButton(style: .icon(symbolName: "pause.fill"))
    private let resumeButton = ComposerTopContentButton(style: .icon(symbolName: "play.fill"))
    private let deleteButton = ComposerTopContentButton(style: .icon(symbolName: "trash"))
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
        case .goalStatus(let configuration):
            configureGoalStatus(configuration)
        case .inlineBanner(let configuration):
            configureInlineBanner(configuration)
        case .stagedContext(let configuration):
            configureStagedContext(configuration)
        }
        messageField.setAccessibilityLabel(messageField.stringValue)
        updateAppearance()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func configureGoalStatus(_ configuration: AppKitChatComposerTopContentView.GoalStatusConfiguration) {
        content = .goalStatus(configuration)
        messageField.stringValue = configuration.snapshot.status.composerTitle
        messageField.font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
        messageField.lineBreakMode = .byTruncatingTail
        messageField.maximumNumberOfLines = 1
        objectiveField.stringValue = configuration.snapshot.objective
        objectiveField.lineBreakMode = .byTruncatingTail
        objectiveField.maximumNumberOfLines = 1
        objectiveField.isHidden = false
        let metadata = Self.goalMetadata(for: configuration)
        metadataField.stringValue = metadata
        metadataField.lineBreakMode = .byTruncatingTail
        metadataField.maximumNumberOfLines = 1
        metadataField.isHidden = metadata.isEmpty
        actionButton.isHidden = true
        actionButton.actionHandler = nil
        pauseButton.configure(title: "Pause goal", isEnabled: configuration.onPause != nil)
        pauseButton.actionHandler = configuration.onPause
        pauseButton.isHidden = configuration.onPause == nil
        resumeButton.configure(title: "Resume goal", isEnabled: configuration.onResume != nil)
        resumeButton.actionHandler = configuration.onResume
        resumeButton.isHidden = configuration.onResume == nil
        deleteButton.configure(title: "Delete goal", isEnabled: configuration.onDelete != nil)
        deleteButton.actionHandler = configuration.onDelete
        deleteButton.isHidden = configuration.onDelete == nil
        dismissButton.actionHandler = configuration.onDismissTerminal
        dismissButton.isHidden = configuration.onDismissTerminal == nil
        dismissButton.setAccessibilityLabel("Dismiss goal status")
        iconView.image = symbolImage(named: "target", pointSize: 15, weight: .semibold)
    }

    private func configureInlineBanner(_ configuration: AppKitChatComposerTopContentView.InlineBannerConfiguration) {
        content = .inlineBanner(configuration)
        messageField.stringValue = configuration.message
        messageField.font = NSFont.preferredFont(forTextStyle: .subheadline)
        messageField.lineBreakMode = .byWordWrapping
        messageField.maximumNumberOfLines = 0
        objectiveField.isHidden = true
        metadataField.isHidden = true
        actionButton.configure(title: configuration.actionTitle ?? "", isEnabled: configuration.actionTitle != nil)
        actionButton.actionHandler = configuration.onAction
        actionButton.isHidden = configuration.actionTitle == nil || configuration.onAction == nil
        pauseButton.isHidden = true
        pauseButton.actionHandler = nil
        resumeButton.isHidden = true
        resumeButton.actionHandler = nil
        deleteButton.isHidden = true
        deleteButton.actionHandler = nil
        dismissButton.actionHandler = configuration.onDismiss
        dismissButton.isHidden = configuration.onDismiss == nil
        dismissButton.setAccessibilityLabel("Dismiss banner")
        iconView.image = symbolImage(named: configuration.severity.symbolName, pointSize: 15, weight: .semibold)
    }

    private func configureStagedContext(_ configuration: AppKitChatComposerTopContentView.StagedContextConfiguration) {
        content = .stagedContext(configuration)
        messageField.stringValue = Self.summary(for: configuration.context)
        messageField.font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .medium)
        messageField.lineBreakMode = .byTruncatingTail
        messageField.maximumNumberOfLines = 1
        objectiveField.isHidden = true
        metadataField.isHidden = true
        actionButton.isHidden = true
        actionButton.actionHandler = nil
        pauseButton.isHidden = true
        pauseButton.actionHandler = nil
        resumeButton.isHidden = true
        resumeButton.actionHandler = nil
        deleteButton.isHidden = true
        deleteButton.actionHandler = nil
        dismissButton.isHidden = false
        dismissButton.actionHandler = configuration.onDismiss
        dismissButton.setAccessibilityLabel("Dismiss context")
        iconView.image = symbolImage(named: "paperclip", pointSize: 14, weight: .medium)
    }

    func measuredHeight(for width: CGFloat) -> CGFloat {
        let availableWidth = max(width, 0)
        let textWidth = max(availableWidth - reservedHorizontalWidth, 0)
        let textHeight = measuredContentTextHeight(for: textWidth)
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

        let visibleButtons = visibleTrailingButtons
        var nextButtonMaxX = bounds.maxX - Self.horizontalPadding
        for button in visibleButtons.reversed() {
            let buttonWidth = button === actionButton ? button.intrinsicContentSize.width : Self.iconButtonWidth
            button.frame = NSRect(
                x: nextButtonMaxX - buttonWidth,
                y: Self.verticalPadding + max((contentHeight - Self.buttonHeight) / 2, 0),
                width: buttonWidth,
                height: Self.buttonHeight
            )
            nextButtonMaxX = button.frame.minX - Self.trailingControlSpacing
        }

        let textX = iconView.frame.maxX + Self.iconTextSpacing
        let trailingTextX = visibleButtons.first?.frame.minX ?? (bounds.maxX - Self.horizontalPadding)
        let controlSpacing = visibleButtons.isEmpty ? 0 : Self.trailingControlSpacing
        let textWidth = max(trailingTextX - controlSpacing - textX, 0)
        layoutTextFields(originX: textX, width: textWidth, contentHeight: contentHeight)
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
        case .goalStatus(let configuration):
            let accentColor = configuration.snapshot.status.goalAccentColor
            backgroundView.setLayerFillColor(accentColor, alpha: 0.12)
            backgroundView.setLayerStrokeColor(accentColor, alpha: configuration.snapshot.status.isTerminal ? 0.35 : 0.24)
            backgroundView.layer?.borderWidth = 1
            iconView.setDynamicContentTintColor(accentColor)
            messageField.textColor = .labelColor
            objectiveField.textColor = .secondaryLabelColor
            metadataField.textColor = configuration.actionError == nil ? .tertiaryLabelColor : .systemRed
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
            objectiveField.textColor = .secondaryLabelColor
            metadataField.textColor = .tertiaryLabelColor
        }
        actionButton.needsDisplay = true
        pauseButton.needsDisplay = true
        resumeButton.needsDisplay = true
        deleteButton.needsDisplay = true
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

        objectiveField.font = NSFont.preferredFont(forTextStyle: .subheadline)
        objectiveField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        objectiveField.isHidden = true
        backgroundView.addSubview(objectiveField)

        metadataField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        metadataField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metadataField.isHidden = true
        backgroundView.addSubview(metadataField)

        actionButton.isHidden = true
        backgroundView.addSubview(actionButton)

        pauseButton.isHidden = true
        backgroundView.addSubview(pauseButton)

        resumeButton.isHidden = true
        backgroundView.addSubview(resumeButton)

        deleteButton.isHidden = true
        backgroundView.addSubview(deleteButton)

        dismissButton.isHidden = true
        dismissButton.setAccessibilityLabel("Dismiss")
        backgroundView.addSubview(dismissButton)
    }

    private var reservedHorizontalWidth: CGFloat {
        let controlsWidth = visibleTrailingButtons.reduce(CGFloat(0)) { partial, button in
            partial + (button === actionButton ? button.intrinsicContentSize.width : Self.iconButtonWidth)
        }
        let controlsSpacing = CGFloat(visibleTrailingButtons.count) * Self.trailingControlSpacing
        return Self.horizontalPadding * 2 + Self.iconSize + Self.iconTextSpacing + controlsWidth + controlsSpacing
    }

    private var visibleTrailingButtons: [ComposerTopContentButton] {
        [actionButton, pauseButton, resumeButton, deleteButton, dismissButton].filter { !$0.isHidden }
    }

    private func layoutTextFields(originX: CGFloat, width: CGFloat, contentHeight: CGFloat) {
        guard isGoalContent else {
            let textHeight = measuredTextHeight(for: messageField, width: width)
            messageField.frame = NSRect(
                x: originX,
                y: Self.verticalPadding + max((contentHeight - textHeight) / 2, 0),
                width: width,
                height: textHeight
            )
            objectiveField.frame = .zero
            metadataField.frame = .zero
            return
        }

        let titleHeight = measuredTextHeight(for: messageField, width: width)
        let objectiveHeight = measuredTextHeight(for: objectiveField, width: width)
        let metadataHeight = metadataField.isHidden ? 0 : measuredTextHeight(for: metadataField, width: width)
        let metadataSpacing = metadataField.isHidden ? 0 : Self.goalTextSpacing
        let stackHeight = titleHeight + Self.goalTextSpacing + objectiveHeight + metadataSpacing + metadataHeight
        var nextY = Self.verticalPadding + max((contentHeight - stackHeight) / 2, 0)
        messageField.frame = NSRect(x: originX, y: nextY, width: width, height: titleHeight)
        nextY += titleHeight + Self.goalTextSpacing
        objectiveField.frame = NSRect(x: originX, y: nextY, width: width, height: objectiveHeight)
        nextY += objectiveHeight + metadataSpacing
        metadataField.frame = metadataField.isHidden ? .zero : NSRect(x: originX, y: nextY, width: width, height: metadataHeight)
    }

    private var isGoalContent: Bool {
        if case .goalStatus = content {
            return true
        }
        return false
    }

    private func measuredContentTextHeight(for width: CGFloat) -> CGFloat {
        guard isGoalContent else {
            return measuredTextHeight(for: messageField, width: width)
        }
        let metadataHeight = metadataField.isHidden ? 0 : measuredTextHeight(for: metadataField, width: width)
        let metadataSpacing = metadataField.isHidden ? 0 : Self.goalTextSpacing
        return measuredTextHeight(for: messageField, width: width)
            + Self.goalTextSpacing
            + measuredTextHeight(for: objectiveField, width: width)
            + metadataSpacing
            + metadataHeight
    }

    private func measuredTextHeight(for field: NSTextField, width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return field.fittingSize.height
        }
        let rect = field.attributedStringValue.boundingRect(
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

    private static func goalMetadata(for configuration: AppKitChatComposerTopContentView.GoalStatusConfiguration) -> String {
        var parts: [String] = []
        if let elapsedSeconds = configuration.snapshot.elapsedSeconds {
            parts.append(elapsedText(seconds: elapsedSeconds))
        }
        if let turnCount = configuration.snapshot.turnCount {
            parts.append("\(turnCount) \(turnCount == 1 ? "turn" : "turns")")
        }
        if let tokenCount = configuration.snapshot.tokenCount {
            let tokenText = NumberFormatter.localizedString(from: NSNumber(value: tokenCount), number: .decimal)
            parts.append("\(tokenText) tokens")
        }
        if let reason = configuration.snapshot.statusReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            parts.append(reason)
        }
        if let actionError = configuration.actionError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !actionError.isEmpty {
            parts.append(actionError)
        }
        return parts.joined(separator: " | ")
    }

    private static func elapsedText(seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    private static let cornerRadius: CGFloat = 14
    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 10
    private static let iconSize: CGFloat = 16
    private static let iconTextSpacing: CGFloat = 12
    private static let goalTextSpacing: CGFloat = 2
    private static let trailingControlSpacing: CGFloat = 8
    private static let iconButtonWidth: CGFloat = 22
    private static let buttonHeight: CGFloat = 22
}
