import AppKit
import BlockInputKit
import SwiftUI

enum AppKitChatQueuedMessagesLayout {
    static let rowLeadingPadding: CGFloat = 10
    static let rowTrailingPadding: CGFloat = 10
    static let rowActionIconButtonSize: CGFloat = 30
    static let pauseResumeButtonHorizontalPadding: CGFloat = 12
}

@MainActor
struct AppKitChatQueuedMessagesConfiguration {
    let queuedMessages: [QueuedMessage]
    let supportsMidTurnSteering: Bool
    let isTurnActive: Bool
    let inFlightQueuedMessageID: UUID?
    let borderWidth: CGFloat
    let pauseHeaderTitle: String?
    let pauseHeaderActionTitle: String
    let markdownBaseURL: URL?
    let onOpenMarkdownLink: (URL) -> Void
    let onOpenMarkdownImage: (BlockInputImage, URL?) -> Void
    let onResume: () -> Void
    let onSteer: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onDismiss: (UUID) -> Void

    static let empty = AppKitChatQueuedMessagesConfiguration(
        queuedMessages: [],
        supportsMidTurnSteering: false,
        isTurnActive: false,
        inFlightQueuedMessageID: nil,
        borderWidth: 1,
        pauseHeaderTitle: nil,
        pauseHeaderActionTitle: "Resume",
        onResume: {},
        onSteer: { _ in },
        onEdit: { _ in },
        onDismiss: { _ in }
    )

    init(
        queuedMessages: [QueuedMessage],
        supportsMidTurnSteering: Bool,
        isTurnActive: Bool,
        inFlightQueuedMessageID: UUID?,
        borderWidth: CGFloat,
        pauseHeaderTitle: String? = nil,
        pauseHeaderActionTitle: String = "Resume",
        markdownBaseURL: URL? = nil,
        onOpenMarkdownLink: @escaping (URL) -> Void = { _ in },
        onOpenMarkdownImage: @escaping (BlockInputImage, URL?) -> Void = { _, _ in },
        onResume: @escaping () -> Void = {},
        onSteer: @escaping (UUID) -> Void,
        onEdit: @escaping (UUID) -> Void,
        onDismiss: @escaping (UUID) -> Void
    ) {
        self.queuedMessages = queuedMessages
        self.supportsMidTurnSteering = supportsMidTurnSteering
        self.isTurnActive = isTurnActive
        self.inFlightQueuedMessageID = inFlightQueuedMessageID
        self.borderWidth = borderWidth
        self.pauseHeaderTitle = pauseHeaderTitle
        self.pauseHeaderActionTitle = pauseHeaderActionTitle
        self.markdownBaseURL = markdownBaseURL
        self.onOpenMarkdownLink = onOpenMarkdownLink
        self.onOpenMarkdownImage = onOpenMarkdownImage
        self.onResume = onResume
        self.onSteer = onSteer
        self.onEdit = onEdit
        self.onDismiss = onDismiss
    }
}

/// Native queued-message list rendered above the composer editor.
///
/// The production AppKit composer panel owns this section so queued rows cannot
/// stretch editor/action-row spacing through SwiftUI layout.
@MainActor
final class AppKitChatQueuedMessagesView: NSView {
    private var pauseHeaderView: AppKitChatQueuedMessagesPauseHeaderView?
    private var rows: [AppKitChatQueuedMessageRowView] = []
    private var configuration = AppKitChatQueuedMessagesConfiguration.empty

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(width: bounds.width))
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(width: bounds.width))
    }

    func configure(_ configuration: AppKitChatQueuedMessagesConfiguration) {
        self.configuration = configuration
        updatePauseHeader()
        rebuildRowsIfNeeded()
        for (index, row) in rows.enumerated() {
            let message = configuration.queuedMessages[index]
            row.configure(
                .init(
                    message: message,
                    showsDivider: index < configuration.queuedMessages.count - 1,
                    isSteerDisabled: !configuration.supportsMidTurnSteering ||
                        !configuration.isTurnActive ||
                        configuration.inFlightQueuedMessageID != nil,
                    areActionsDisabled: configuration.inFlightQueuedMessageID != nil,
                    markdownBaseURL: configuration.markdownBaseURL,
                    onOpenMarkdownLink: configuration.onOpenMarkdownLink,
                    onOpenMarkdownImage: configuration.onOpenMarkdownImage,
                    onSteer: { [configuration] in configuration.onSteer(message.id) },
                    onEdit: { [configuration] in configuration.onEdit(message.id) },
                    onDismiss: { [configuration] in configuration.onDismiss(message.id) }
                )
            )
        }
        isHidden = configuration.queuedMessages.isEmpty
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        pauseHeaderView?.updateAppearance()
        rows.forEach { $0.updateImages() }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        var nextY: CGFloat = 0
        if let pauseHeaderView {
            let height = pauseHeaderView.measuredHeight
            pauseHeaderView.frame = NSRect(x: 0, y: nextY, width: bounds.width, height: height)
            nextY += height
        }
        for row in rows {
            let height = row.measuredHeight(width: bounds.width)
            row.frame = NSRect(x: 0, y: nextY, width: bounds.width, height: height)
            nextY += height
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !configuration.queuedMessages.isEmpty else {
            return
        }

        let path = NSBezierPath.appKitComposerTopRoundedRect(bounds, radius: 18)
        appKitQueuedMessagesFillColor(in: self).setFill()
        path.fill()

        // Draw only the queue list's outer top border. The editor below owns the
        // shared edge, so a bottom stroke here creates a visible seam.
        appKitQueuedMessagesBorderColor(in: self).setStroke()
        let borderRect = bounds.insetBy(dx: configuration.borderWidth / 2, dy: 0)
        let borderPath = NSBezierPath.appKitComposerTopRoundedBorder(borderRect, radius: 18)
        borderPath.lineWidth = configuration.borderWidth
        borderPath.stroke()
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        guard !configuration.queuedMessages.isEmpty else {
            return 0
        }
        let measuredWidth = width > 0 ? width : bounds.width
        let headerHeight = pauseHeaderView?.measuredHeight ?? 0
        return rows.reduce(headerHeight) { partial, row in
            partial + row.measuredHeight(width: measuredWidth)
        }
    }

    private func updatePauseHeader() {
        guard let title = configuration.pauseHeaderTitle,
              !configuration.queuedMessages.isEmpty else {
            pauseHeaderView?.removeFromSuperview()
            pauseHeaderView = nil
            return
        }

        let header = pauseHeaderView ?? AppKitChatQueuedMessagesPauseHeaderView()
        if pauseHeaderView == nil {
            pauseHeaderView = header
            addSubview(header)
        }
        header.configure(
            title: title,
            actionTitle: configuration.pauseHeaderActionTitle,
            onResume: configuration.onResume
        )
    }

    private func rebuildRowsIfNeeded() {
        guard rows.map(\.messageID) != configuration.queuedMessages.map(\.id) else {
            return
        }

        rows.forEach { $0.removeFromSuperview() }
        rows = configuration.queuedMessages.map { _ in
            let row = AppKitChatQueuedMessageRowView()
            addSubview(row)
            return row
        }
    }
}

private final class AppKitChatQueuedMessageRowView: NSView {
    struct Configuration {
        let message: QueuedMessage
        let showsDivider: Bool
        let isSteerDisabled: Bool
        let areActionsDisabled: Bool
        let markdownBaseURL: URL?
        let onOpenMarkdownLink: (URL) -> Void
        let onOpenMarkdownImage: (BlockInputImage, URL?) -> Void
        let onSteer: () -> Void
        let onEdit: () -> Void
        let onDismiss: () -> Void
    }

    private let iconView = NSImageView()
    private let markdownView = AppKitMarkdownView(
        document: AppMarkdownDocument(content: AttributedString("")),
        inlineCodeStyle: .composer
    )
    private var messageDocument = AppMarkdownDocument(content: AttributedString(""))
    private let contextIconView = NSImageView()
    private let contextField = NSTextField(labelWithString: "Context attached")
    private let steerButton = AppKitChatQueuedMessageSteerButton()
    private let editButton = AppKitChatQueuedMessageIconButton(symbolName: "pencil", isDestructive: false)
    private let dismissButton = AppKitChatQueuedMessageIconButton(symbolName: "trash", isDestructive: true)
    private var showsDivider = false

    private(set) var messageID = UUID()

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(width: bounds.width))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(_ configuration: Configuration) {
        let message = configuration.message
        messageID = message.id
        showsDivider = configuration.showsDivider
        messageDocument = AppMarkdownParser(
            composerChipProvider: ChatComposerTextSupport.composerTextChips(in:)
        ).documentPreservingSource(for: message.text)
        markdownView.configure(
            document: messageDocument,
            inlineCodeStyle: .composer,
            imageBaseURL: configuration.markdownBaseURL
        )
        markdownView.onOpenLink = configuration.onOpenMarkdownLink
        markdownView.onOpenImage = configuration.onOpenMarkdownImage
        contextIconView.isHidden = message.stagedContext == nil
        contextField.isHidden = message.stagedContext == nil
        steerButton.configure(isEnabled: !configuration.isSteerDisabled)
        steerButton.actionHandler = configuration.onSteer
        editButton.configure(isEnabled: !configuration.areActionsDisabled)
        editButton.actionHandler = configuration.onEdit
        dismissButton.configure(isEnabled: !configuration.areActionsDisabled)
        dismissButton.actionHandler = configuration.onDismiss
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateImages()
        needsDisplay = true
    }

    func updateImages() {
        let iconColor = appKitComposerPrimaryColor(in: self, opacity: 0.35)
        iconView.contentTintColor = iconColor
        contextIconView.contentTintColor = iconColor
        iconView.image = Self.symbolImage(named: "clock")
        contextIconView.image = Self.symbolImage(named: "paperclip")
    }

    override func layout() {
        super.layout()
        let leadingPadding = AppKitChatQueuedMessagesLayout.rowLeadingPadding
        let trailingPadding = AppKitChatQueuedMessagesLayout.rowTrailingPadding
        let verticalPadding: CGFloat = 10
        let iconSize: CGFloat = 14
        let spacing: CGFloat = 12
        // 82pt steer + 8pt gaps + two 30pt icon buttons. Keep this equal to the
        // laid-out controls so the trash icon's trailing inset mirrors the row's
        // leading inset.
        let actionWidth: CGFloat = 158
        let actionsX = bounds.maxX - trailingPadding - actionWidth
        iconView.frame = NSRect(x: leadingPadding, y: floor((bounds.height - iconSize) / 2), width: iconSize, height: iconSize)

        let textX = leadingPadding + iconSize + spacing
        let textWidth = max(0, actionsX - textX - 16)
        let textHeight = measuredTextHeight(width: textWidth)
        // Single-line Markdown glyphs sit optically high inside their measured bounds; align them with the clock symbol.
        // Wrapped text fills the row, so keep it truly centered or the bottom inset visibly shrinks.
        // One measured line is ~20pt (the `measuredTextHeight` floor); two lines are ~33pt+.
        let singleLineHeightThreshold: CGFloat = 26
        let compactTextYOffset: CGFloat = textHeight <= singleLineHeightThreshold ? 2 : 0
        let textY = contextField.isHidden ?
            floor((bounds.height - textHeight) / 2 + compactTextYOffset) :
            verticalPadding
        markdownView.frame = NSRect(x: textX, y: textY, width: textWidth, height: textHeight)
        markdownView.needsLayout = true
        markdownView.layoutSubtreeIfNeeded()

        if !contextField.isHidden {
            let contextTextHeight = ceil(contextField.intrinsicContentSize.height)
            let contextLineHeight = max(iconSize, contextTextHeight)
            let contextLineY = verticalPadding + textHeight + 5
            contextIconView.frame = NSRect(
                x: textX,
                y: contextLineY + floor((contextLineHeight - iconSize) / 2),
                width: iconSize,
                height: iconSize
            )
            contextField.frame = NSRect(
                x: textX + iconSize + 6,
                y: contextLineY + floor((contextLineHeight - contextTextHeight) / 2),
                width: max(0, textWidth - iconSize - 6),
                height: contextTextHeight
            )
        }

        var nextX = actionsX
        steerButton.frame = NSRect(x: nextX, y: floor((bounds.height - 30) / 2), width: 82, height: 30)
        nextX += 90
        layoutIconActionButton(editButton, actionX: nextX)
        nextX += 38
        layoutIconActionButton(dismissButton, actionX: nextX)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if showsDivider {
            appKitComposerPrimaryColor(in: self, opacity: 0.1).setFill()
            NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        }
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let leadingPadding = AppKitChatQueuedMessagesLayout.rowLeadingPadding
        let trailingPadding = AppKitChatQueuedMessagesLayout.rowTrailingPadding
        let textX = leadingPadding + 14 + 12
        let textWidth = max(0, width - textX - 16 - 158 - trailingPadding)
        let contextHeight: CGFloat = contextField.isHidden ? 0 : 21
        let contextSpacing: CGFloat = contextField.isHidden ? 0 : 5
        let contentHeight = measuredTextHeight(width: textWidth) + contextSpacing + contextHeight
        let minimumHeight: CGFloat = contextField.isHidden ? 44 : 50
        let verticalPadding: CGFloat = contextField.isHidden ? 16 : 20
        return ceil(max(minimumHeight, contentHeight + verticalPadding))
    }

    private func setup() {
        [iconView, markdownView, contextIconView, contextField, steerButton, editButton, dismissButton].forEach(addSubview)
        updateImages()
        markdownView.translatesAutoresizingMaskIntoConstraints = true
        contextField.font = .preferredFont(forTextStyle: .caption1)
        contextField.textColor = .secondaryLabelColor
        editButton.setAccessibilityLabel("Edit queued message")
        dismissButton.setAccessibilityLabel("Discard queued message")
    }

    private func layoutIconActionButton(_ button: NSView, actionX: CGFloat) {
        let size = AppKitChatQueuedMessagesLayout.rowActionIconButtonSize
        button.frame = NSRect(
            x: actionX,
            y: floor((bounds.height - size) / 2),
            width: size,
            height: size
        )
    }

    private func measuredTextHeight(width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return 20
        }
        let colorScheme = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ColorScheme.dark : .light
        let measurement = AppKitMarkdownLayoutMeasurer(
            document: messageDocument,
            inlineCodeStyle: .composer,
            colorScheme: colorScheme
        ).measure(width: width)
        return ceil(max(20, measurement.contentHeight))
    }

    private static func symbolImage(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?
            .copy() as? NSImage
        image?.isTemplate = true
        return image
    }
}

private extension NSBezierPath {
    static func appKitComposerTopRoundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        let radius = min(radius, rect.width / 2, rect.height)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        path.curve(
            to: NSPoint(x: rect.minX + radius, y: rect.minY),
            controlPoint1: NSPoint(x: rect.minX, y: rect.minY + radius * 0.45),
            controlPoint2: NSPoint(x: rect.minX + radius * 0.45, y: rect.minY)
        )
        path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        path.curve(
            to: NSPoint(x: rect.maxX, y: rect.minY + radius),
            controlPoint1: NSPoint(x: rect.maxX - radius * 0.45, y: rect.minY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + radius * 0.45)
        )
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.close()
        return path
    }

    static func appKitComposerTopRoundedBorder(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        let radius = min(radius, rect.width / 2, rect.height)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        path.curve(
            to: NSPoint(x: rect.minX + radius, y: rect.minY),
            controlPoint1: NSPoint(x: rect.minX, y: rect.minY + radius * 0.45),
            controlPoint2: NSPoint(x: rect.minX + radius * 0.45, y: rect.minY)
        )
        path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        path.curve(
            to: NSPoint(x: rect.maxX, y: rect.minY + radius),
            controlPoint1: NSPoint(x: rect.maxX - radius * 0.45, y: rect.minY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + radius * 0.45)
        )
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

@MainActor
func appKitComposerPrimaryColor(in view: NSView, opacity: CGFloat) -> NSColor {
    // Match SwiftUI `Color.primary.opacity(...)`: resolve the dynamic color first
    // and multiply the resolved alpha instead of replacing it.
    let resolved = NSColor.labelColor.resolved(for: view.appKitRenderingAppearance)
    return resolved.withAlphaComponent(resolved.alphaComponent * opacity)
}

@MainActor
func appKitComposerSecondaryColor(in view: NSView, opacity: CGFloat) -> NSColor {
    // Match SwiftUI `Color.secondary.opacity(...)`: resolve the dynamic color first
    // and multiply the resolved alpha instead of replacing it.
    let resolved = NSColor.secondaryLabelColor.resolved(for: view.appKitRenderingAppearance)
    return resolved.withAlphaComponent(resolved.alphaComponent * opacity)
}

@MainActor
func appKitQueuedMessagesFillColor(in view: NSView) -> NSColor {
    BlockInputComposerStyle.editorFillColor.resolved(for: view.appKitRenderingAppearance)
}

@MainActor
func appKitQueuedMessagesBorderColor(in view: NSView) -> NSColor {
    BlockInputComposerStyle.editorBorderColor.resolved(for: view.appKitRenderingAppearance)
}
