import AppKit
import BlockInputKit

struct AppKitChatComposerPanelConfiguration {
    let bodyConfiguration: AppKitChatComposerBodyConfiguration
    let topContentConfiguration: AppKitChatComposerTopContentView.Configuration
    let queuedMessagesConfiguration: AppKitChatQueuedMessagesConfiguration?
    let actionRowConfiguration: ChatComposerActionRowView.Configuration?
    let interactionOverlayConfiguration: AppKitComposerOverlayConfiguration?
    let showsTopDivider: Bool
    let layout: AppKitChatComposerPanelView.Layout

    init(
        bodyConfiguration: AppKitChatComposerBodyConfiguration,
        topContentConfiguration: AppKitChatComposerTopContentView.Configuration = .empty,
        queuedMessagesConfiguration: AppKitChatQueuedMessagesConfiguration? = nil,
        actionRowConfiguration: ChatComposerActionRowView.Configuration? = nil,
        interactionOverlayConfiguration: AppKitComposerOverlayConfiguration? = nil,
        showsTopDivider: Bool,
        layout: AppKitChatComposerPanelView.Layout
    ) {
        self.bodyConfiguration = bodyConfiguration
        self.topContentConfiguration = topContentConfiguration
        self.queuedMessagesConfiguration = queuedMessagesConfiguration
        self.actionRowConfiguration = actionRowConfiguration
        self.interactionOverlayConfiguration = interactionOverlayConfiguration
        self.showsTopDivider = showsTopDivider
        self.layout = layout
    }
}

/// AppKit owner for the composer panel shell.
///
/// Production chat surfaces host BlockInputKit directly so the editor, queued
/// messages, and action row live in one AppKit layout path.
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

    let editorController = AppKitChatComposerEditorController()
    private let topContentView = AppKitChatComposerTopContentView()
    private let queuedMessagesView = AppKitChatQueuedMessagesView()
    let attachmentStripView = AppKitComposerAttachmentStripView()
    private let actionRow = ChatComposerActionRowView()
    private let dividerView = NSView()
    let fileDropOverlayView = AppKitComposerFileDropOverlayView()
    private let interactionOverlayView = AppKitComposerOverlayView()
    var cachedFileDropSequenceNumber: Int?
    var cachedFileDropHasReadableFileURLs = false

    var configuration: AppKitChatComposerPanelConfiguration?
    private var showsTopDivider = false
    private var deferredPreferredHeightAnimation: Bool?

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard hit === self,
              let editorView = editorController.view,
              !editorView.isHidden,
              editorView.frame.contains(point) else {
            return hit
        }
        let editorPoint = convert(point, to: editorView)
        return editorView.hitTest(editorPoint) ?? editorView
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
        let previousEditorTopOffset = currentEditorTopOffset()
        deferredPreferredHeightAnimation = true
        self.configuration = configuration
        topContentView.configure(configuration.topContentConfiguration)
        configureQueuedMessages(configuration.queuedMessagesConfiguration)
        configureAttachmentStrip(configuration.bodyConfiguration)
        configureEditor(configuration.bodyConfiguration)
        configureActionRow(configuration.actionRowConfiguration)
        configureInteractionOverlay(configuration.interactionOverlayConfiguration)
        configureDividerVisibility(configuration.showsTopDivider)
        // Queue and top-content insertions move the editor's y-origin. Apply
        // those structural height changes immediately so the editor and action
        // row stay bottom-pinned instead of riding the outer height animation.
        let editorTopOffsetChanged = didEditorTopOffsetChange(from: previousEditorTopOffset)
        let animateSurfaceHeight = (deferredPreferredHeightAnimation ?? true) && !editorTopOffsetChanged
        deferredPreferredHeightAnimation = nil
        invalidatePreferredHeight(animateSurfaceHeight: animateSurfaceHeight)
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
        currentY = layoutAttachmentStrip(configuration: configuration, contentWidth: contentWidth, currentY: currentY)
        currentY = layoutEditor(configuration: configuration, contentWidth: contentWidth, currentY: currentY)
        if configuration.actionRowConfiguration != nil {
            actionRow.frame = NSRect(
                x: configuration.layout.horizontalPadding.left,
                y: currentY + configuration.layout.actionRowSpacing,
                width: contentWidth,
                height: actionRow.intrinsicContentSize.height
            )
        }
        layoutFileDropOverlay(configuration: configuration)
        layoutInteractionOverlay(configuration: configuration)
        dividerView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = true
        registerForDraggedTypes([.fileURL])

        addSubview(topContentView)
        addSubview(queuedMessagesView)
        addSubview(attachmentStripView)
        editorController.onPreferredSizeInvalidated = { [weak self] animateSurfaceHeight in
            self?.handlePreferredSizeInvalidated(animateSurfaceHeight: animateSurfaceHeight)
        }
        actionRow.isHidden = true
        addSubview(actionRow)

        addSubview(fileDropOverlayView)

        interactionOverlayView.isHidden = true
        interactionOverlayView.onPreferredSizeInvalidated = { [weak self] in
            self?.invalidatePreferredHeight()
        }
        addSubview(interactionOverlayView)

        dividerView.wantsLayer = true
        dividerView.isHidden = true
        dividerView.alphaValue = 0
        addSubview(dividerView)
        updateColors()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil else {
            return
        }
        editorController.detach()
    }

    private func configureActionRow(_ configuration: ChatComposerActionRowView.Configuration?) {
        guard let configuration else {
            actionRow.isHidden = true
            return
        }
        actionRow.isHidden = false
        var actionRowConfiguration = configuration
        actionRowConfiguration.onAddPhotosAndFiles = { [weak self] in
            self?.presentPhotosAndFilesPicker()
        }
        actionRow.configure(actionRowConfiguration)
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

    private func layoutEditor(
        configuration: AppKitChatComposerPanelConfiguration,
        contentWidth: CGFloat,
        currentY: CGFloat
    ) -> CGFloat {
        guard let editorView = editorController.view else {
            return currentY
        }
        let editorFrame = editorController.editorFrame(
            origin: NSPoint(x: configuration.layout.horizontalPadding.left, y: currentY),
            width: contentWidth
        )
        editorView.frame = editorFrame
        return currentY + editorController.measuredHeight(width: contentWidth)
    }

    private func layoutInteractionOverlay(configuration: AppKitChatComposerPanelConfiguration) {
        guard configuration.interactionOverlayConfiguration != nil else {
            interactionOverlayView.frame = .zero
            return
        }

        interactionOverlayView.frame = bounds
        interactionOverlayView.ensureFocusIfNeeded()
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

    private func configureEditor(_ configuration: AppKitChatComposerBodyConfiguration) {
        let previousView = editorController.view
        editorController.configure(configuration)
        guard let editorView = editorController.view,
              editorView !== previousView || editorView.superview == nil else {
            return
        }
        previousView?.removeFromSuperview()
        addSubview(editorView, positioned: .below, relativeTo: actionRow)
    }

    private func configureInteractionOverlay(_ configuration: AppKitComposerOverlayConfiguration?) {
        guard let configuration else {
            interactionOverlayView.configure(nil)
            interactionOverlayView.isHidden = true
            interactionOverlayView.frame = .zero
            setNormalComposerOverlayHidden(false)
            return
        }

        interactionOverlayView.isHidden = false
        interactionOverlayView.configure(configuration, contentInsets: self.configuration?.layout.horizontalPadding ?? NSEdgeInsetsZero)
        setNormalComposerOverlayHidden(true)
        addSubview(interactionOverlayView, positioned: .above, relativeTo: nil)
        interactionOverlayView.ensureFocusIfNeeded()
    }

    private func setNormalComposerOverlayHidden(_ isHidden: Bool) {
        [topContentView, queuedMessagesView, attachmentStripView, editorController.view, actionRow].forEach {
            $0?.setAccessibilityHidden(isHidden)
        }
        topContentView.isHidden = isHidden || !topContentView.hasContent
        queuedMessagesView.isHidden = isHidden || (configuration?.queuedMessagesConfiguration?.queuedMessages.isEmpty ?? true)
        attachmentStripView.isHidden = isHidden || (configuration?.bodyConfiguration.attachments.isEmpty ?? true)
        editorController.view?.isHidden = isHidden
        actionRow.isHidden = isHidden || configuration?.actionRowConfiguration == nil
        if isHidden {
            setFileDropOverlayActive(false)
        }
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
        if topContentView.hasContent {
            return configuration.layout.topContentSpacing
        }
        if !configuration.bodyConfiguration.attachments.isEmpty,
           configuration.queuedMessagesConfiguration?.queuedMessages.isEmpty != false {
            return ChatComposerPanelLayout.nativeInputTopPadding
        }
        return 0
    }

    private func currentEditorTopOffset() -> CGFloat? {
        guard let configuration else {
            return nil
        }
        return editorTopOffset(for: bounds.width, configuration: configuration)
    }

    private func editorTopOffset(for width: CGFloat, configuration: AppKitChatComposerPanelConfiguration) -> CGFloat {
        let contentWidth = contentWidth(for: width, layout: configuration.layout)
        var offset = topPadding(for: configuration)
        if topContentView.hasContent {
            offset += measuredHeight(of: topContentView, width: contentWidth) + configuration.layout.topContentSpacing
        }
        if let queuedMessagesConfiguration = configuration.queuedMessagesConfiguration,
           !queuedMessagesConfiguration.queuedMessages.isEmpty {
            if !topContentView.hasContent {
                offset += configuration.layout.queuedMessagesTopPadding
            }
            offset += queuedMessagesView.measuredHeight(width: contentWidth)
        }
        if !configuration.bodyConfiguration.attachments.isEmpty {
            offset += attachmentStripView.measuredHeight(width: contentWidth)
        }
        return offset + editorController.topPadding
    }

    private func didEditorTopOffsetChange(from previousOffset: CGFloat?) -> Bool {
        guard let previousOffset,
              let currentOffset = currentEditorTopOffset() else {
            return false
        }
        return abs(previousOffset - currentOffset) > 0.5
    }

    private func updateColors() {
        dividerView.layer?.backgroundColor = NSColor.separatorColor.resolved(for: appKitRenderingAppearance).cgColor
    }

    private func measuredHeight(for width: CGFloat) -> CGFloat {
        guard let configuration else {
            return 0
        }
        let normalHeight = normalMeasuredHeight(for: width, configuration: configuration)
        guard configuration.interactionOverlayConfiguration != nil else {
            return normalHeight
        }
        return ceil(interactionOverlayView.measuredHeight(width: width))
    }

    private func normalMeasuredHeight(for width: CGFloat, configuration: AppKitChatComposerPanelConfiguration) -> CGFloat {
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
        if !configuration.bodyConfiguration.attachments.isEmpty {
            height += attachmentStripView.measuredHeight(width: contentWidth)
        }
        height += editorController.measuredHeight(width: contentWidth)
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

    private func handlePreferredSizeInvalidated(animateSurfaceHeight: Bool) {
        guard let deferredPreferredHeightAnimation else {
            invalidatePreferredHeight(animateSurfaceHeight: animateSurfaceHeight)
            return
        }
        self.deferredPreferredHeightAnimation = deferredPreferredHeightAnimation && animateSurfaceHeight
    }

    private func invalidatePreferredHeight(animateSurfaceHeight: Bool = true) {
        invalidateIntrinsicContentSize()
        needsLayout = true
        if let surfaceView = superview as? AppKitChatSurfaceView {
            surfaceView.layoutPreferredComposerHeightChange(animated: animateSurfaceHeight)
        } else {
            superview?.needsLayout = true
        }
    }

}

#if DEBUG
extension AppKitChatComposerPanelView {
    var editorControllerForTesting: AppKitChatComposerEditorController { editorController }
    var attachmentStripViewForTesting: AppKitComposerAttachmentStripView { attachmentStripView }
    var fileDropOverlayViewForTesting: AppKitComposerFileDropOverlayView { fileDropOverlayView }
    var interactionOverlayViewForTesting: AppKitComposerOverlayView { interactionOverlayView }
}
#endif
