import AppKit

struct AppKitChatComposerPanelConfiguration {
    let bodyConfiguration: AppKitChatComposerBodyConfiguration
    let topContentConfiguration: AppKitChatComposerTopContentView.Configuration
    let queuedMessagesConfiguration: AppKitChatQueuedMessagesConfiguration?
    let actionRowConfiguration: ChatComposerActionRowView.Configuration?
    let showsTopDivider: Bool
    let layout: AppKitChatComposerPanelView.Layout

    init(
        bodyConfiguration: AppKitChatComposerBodyConfiguration,
        topContentConfiguration: AppKitChatComposerTopContentView.Configuration = .empty,
        queuedMessagesConfiguration: AppKitChatQueuedMessagesConfiguration? = nil,
        actionRowConfiguration: ChatComposerActionRowView.Configuration? = nil,
        showsTopDivider: Bool,
        layout: AppKitChatComposerPanelView.Layout
    ) {
        self.bodyConfiguration = bodyConfiguration
        self.topContentConfiguration = topContentConfiguration
        self.queuedMessagesConfiguration = queuedMessagesConfiguration
        self.actionRowConfiguration = actionRowConfiguration
        self.showsTopDivider = showsTopDivider
        self.layout = layout
    }
}

/// AppKit owner for the composer panel shell.
///
/// Production chat surfaces pass a native composer body so the BlockInputKit
/// editor, queued messages, and action row live in one AppKit layout path.
@MainActor
final class AppKitChatComposerPanelView: NSView {
    struct Layout {
        let horizontalPadding: NSEdgeInsets
        let topContentSpacing: CGFloat
        let actionRowSpacing: CGFloat
        let queuedMessagesTopPadding: CGFloat
        /// Clearance below the native action row. Keep this out of the editor
        /// body padding so the editor-to-controls gap stays at `actionRowSpacing`.
        let bottomPadding: CGFloat

        init(
            horizontalPadding: NSEdgeInsets,
            topContentSpacing: CGFloat,
            actionRowSpacing: CGFloat,
            queuedMessagesTopPadding: CGFloat = 16,
            bottomPadding: CGFloat = 0
        ) {
            self.horizontalPadding = horizontalPadding
            self.topContentSpacing = topContentSpacing
            self.actionRowSpacing = actionRowSpacing
            self.queuedMessagesTopPadding = queuedMessagesTopPadding
            self.bottomPadding = bottomPadding
        }
    }

    private let nativeBodyView = AppKitChatComposerBodyView()
    private let topContentView = AppKitChatComposerTopContentView()
    private let queuedMessagesView = AppKitChatQueuedMessagesView()
    private let actionRow = ChatComposerActionRowView()
    private let dividerView = NSView()

    private var configuration: AppKitChatComposerPanelConfiguration?
    private var showsTopDivider = false

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(for: bounds.width))
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(for: bounds.width))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(_ configuration: AppKitChatComposerPanelConfiguration) {
        self.configuration = configuration
        topContentView.configure(configuration.topContentConfiguration)
        configureQueuedMessages(configuration.queuedMessagesConfiguration)
        nativeBodyView.configure(configuration.bodyConfiguration)
        configureActionRow(configuration.actionRowConfiguration)
        configureDividerVisibility(configuration.showsTopDivider)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func layout() {
        super.layout()
        guard let configuration else {
            return
        }

        let contentWidth = contentWidth(for: bounds.width, layout: configuration.layout)
        var currentY = topPadding(for: configuration)
        currentY = layoutTopContent(configuration: configuration, contentWidth: contentWidth, currentY: currentY)
        currentY = layoutQueuedMessages(configuration: configuration, contentWidth: contentWidth, currentY: currentY)
        let bodyHeight = measuredHeight(of: nativeBodyView, width: contentWidth)
        nativeBodyView.frame = NSRect(
            x: configuration.layout.horizontalPadding.left,
            y: currentY,
            width: contentWidth,
            height: bodyHeight
        )
        currentY += bodyHeight
        if configuration.actionRowConfiguration != nil {
            actionRow.frame = NSRect(
                x: configuration.layout.horizontalPadding.left,
                y: currentY + configuration.layout.actionRowSpacing,
                width: contentWidth,
                height: actionRow.intrinsicContentSize.height
            )
        }
        dividerView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    private func setupViews() {
        addSubview(topContentView)
        addSubview(queuedMessagesView)
        nativeBodyView.onPreferredSizeInvalidated = { [weak self] in
            self?.invalidateIntrinsicContentSize()
            self?.needsLayout = true
            self?.superview?.needsLayout = true
        }
        addSubview(nativeBodyView)
        actionRow.isHidden = true
        addSubview(actionRow)

        dividerView.wantsLayer = true
        dividerView.isHidden = true
        dividerView.alphaValue = 0
        addSubview(dividerView)
        updateColors()
    }

    private func configureActionRow(_ configuration: ChatComposerActionRowView.Configuration?) {
        guard let configuration else {
            actionRow.isHidden = true
            return
        }
        actionRow.isHidden = false
        actionRow.configure(configuration)
    }

    private func layoutTopContent(
        configuration: AppKitChatComposerPanelConfiguration,
        contentWidth: CGFloat,
        currentY: CGFloat
    ) -> CGFloat {
        guard topContentView.hasContent else {
            topContentView.frame = .zero
            return currentY
        }
        let topContentHeight = measuredHeight(of: topContentView, width: contentWidth)
        topContentView.frame = NSRect(
            x: configuration.layout.horizontalPadding.left,
            y: currentY,
            width: contentWidth,
            height: topContentHeight
        )
        return currentY + topContentHeight + configuration.layout.topContentSpacing
    }

    private func layoutQueuedMessages(
        configuration: AppKitChatComposerPanelConfiguration,
        contentWidth: CGFloat,
        currentY: CGFloat
    ) -> CGFloat {
        guard let queuedMessagesConfiguration = configuration.queuedMessagesConfiguration,
              !queuedMessagesConfiguration.queuedMessages.isEmpty else {
            queuedMessagesView.frame = .zero
            return currentY
        }
        let queuedY = queuedY(configuration: configuration, currentY: currentY)
        let queuedHeight = queuedMessagesView.measuredHeight(width: contentWidth)
        queuedMessagesView.frame = NSRect(
            x: configuration.layout.horizontalPadding.left,
            y: queuedY,
            width: contentWidth,
            height: queuedHeight
        )
        return queuedY + queuedHeight
    }

    private func queuedY(configuration: AppKitChatComposerPanelConfiguration, currentY: CGFloat) -> CGFloat {
        guard !topContentView.hasContent else {
            return currentY
        }
        return currentY + configuration.layout.queuedMessagesTopPadding
    }

    private func configureQueuedMessages(_ configuration: AppKitChatQueuedMessagesConfiguration?) {
        guard let configuration else {
            queuedMessagesView.configure(.empty)
            return
        }
        queuedMessagesView.configure(configuration)
    }

    private func configureDividerVisibility(_ isVisible: Bool) {
        guard showsTopDivider != isVisible else {
            return
        }

        showsTopDivider = isVisible
        if window == nil {
            dividerView.alphaValue = isVisible ? 1 : 0
            dividerView.isHidden = !isVisible
            return
        }

        if isVisible {
            dividerView.isHidden = false
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dividerView.animator().alphaValue = isVisible ? 1 : 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.showsTopDivider else {
                    return
                }
                self.dividerView.isHidden = true
            }
        }
    }

    private func contentWidth(for width: CGFloat, layout: Layout) -> CGFloat {
        max(0, width - layout.horizontalPadding.left - layout.horizontalPadding.right)
    }

    private func topPadding(for configuration: AppKitChatComposerPanelConfiguration) -> CGFloat {
        topContentView.hasContent ? configuration.layout.topContentSpacing : 0
    }

    private func updateColors() {
        dividerView.layer?.backgroundColor = NSColor.separatorColor.resolved(for: appKitRenderingAppearance).cgColor
    }

    private func measuredHeight(for width: CGFloat) -> CGFloat {
        guard let configuration else {
            return 0
        }
        let contentWidth = contentWidth(for: width, layout: configuration.layout)
        var height = topPadding(for: configuration)
        if topContentView.hasContent {
            height += measuredHeight(of: topContentView, width: contentWidth) + configuration.layout.topContentSpacing
        }
        if let queuedMessagesConfiguration = configuration.queuedMessagesConfiguration,
           !queuedMessagesConfiguration.queuedMessages.isEmpty {
            if !topContentView.hasContent {
                height += configuration.layout.queuedMessagesTopPadding
            }
            height += queuedMessagesView.measuredHeight(width: contentWidth)
        }
        height += measuredHeight(of: nativeBodyView, width: contentWidth)
        if configuration.actionRowConfiguration != nil {
            height += configuration.layout.actionRowSpacing + actionRow.intrinsicContentSize.height + configuration.layout.bottomPadding
        }
        return ceil(height)
    }

    private func measuredHeight(of view: NSView, width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return max(0, ceil(view.fittingSize.height))
        }
        if view.frame.width != width {
            view.frame.size.width = width
            view.needsLayout = true
        }
        view.layoutSubtreeIfNeeded()
        return max(0, ceil(view.fittingSize.height))
    }
}
