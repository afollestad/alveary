import AppKit
import SwiftUI

struct AppKitChatComposerPanelConfiguration {
    let content: AnyView
    let actionRowConfiguration: ChatComposerActionRowView.Configuration?
    let showsTopDivider: Bool
    let hasTopContent: Bool
    let layout: AppKitChatComposerPanelView.Layout

    init(
        content: AnyView,
        actionRowConfiguration: ChatComposerActionRowView.Configuration? = nil,
        showsTopDivider: Bool,
        hasTopContent: Bool,
        layout: AppKitChatComposerPanelView.Layout
    ) {
        self.content = content
        self.actionRowConfiguration = actionRowConfiguration
        self.showsTopDivider = showsTopDivider
        self.hasTopContent = hasTopContent
        self.layout = layout
    }
}

/// AppKit owner for the composer panel shell.
///
/// The inner composer body is still transitional SwiftUI content. This view
/// owns the shell pieces that have regressed during the migration: transparent
/// outer background, horizontal padding, top-content vertical offset, top
/// divider color, native action-row placement, and height measurement.
@MainActor
final class AppKitChatComposerPanelView: NSView {
    struct Layout {
        let horizontalPadding: NSEdgeInsets
        let topContentSpacing: CGFloat
        let actionRowSpacing: CGFloat
    }

    private let contentHost = AppKitChatSurfaceHostingView(rootView: AnyView(EmptyView()))
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
        contentHost.rootView = configuration.content
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
        let topPadding = topPadding(for: configuration)
        let contentHeight = measuredHeight(of: contentHost, width: contentWidth)
        contentHost.frame = NSRect(
            x: configuration.layout.horizontalPadding.left,
            y: topPadding,
            width: contentWidth,
            height: contentHeight
        )
        if configuration.actionRowConfiguration != nil {
            actionRow.frame = NSRect(
                x: configuration.layout.horizontalPadding.left,
                y: topPadding + contentHeight + configuration.layout.actionRowSpacing,
                width: contentWidth,
                height: actionRow.intrinsicContentSize.height
            )
        }
        dividerView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    private func setupViews() {
        contentHost.configureChatSurfaceSizing()
        contentHost.onPreferredSizeInvalidated = { [weak self] in
            self?.invalidateIntrinsicContentSize()
            self?.needsLayout = true
            self?.superview?.needsLayout = true
        }
        addSubview(contentHost)
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
        configuration.hasTopContent ? configuration.layout.topContentSpacing : 0
    }

    private func updateColors() {
        dividerView.layer?.backgroundColor = NSColor.separatorColor.resolved(for: appKitRenderingAppearance).cgColor
    }

    private func measuredHeight(for width: CGFloat) -> CGFloat {
        guard let configuration else {
            return 0
        }
        let contentWidth = contentWidth(for: width, layout: configuration.layout)
        var height = topPadding(for: configuration) + measuredHeight(of: contentHost, width: contentWidth)
        if configuration.actionRowConfiguration != nil {
            height += configuration.layout.actionRowSpacing + actionRow.intrinsicContentSize.height
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
