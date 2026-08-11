@preconcurrency import AppKit

struct AppKitComposerOverlayConfiguration {
    let id: String
    let panelConfiguration: AppKitComposerOverlayPanelView.Configuration
}

enum AppKitComposerOverlayMetrics {
    static let cornerRadius: CGFloat = 18
    static let headerHeight: CGFloat = 28
    static let regularDensity = AppKitComposerOverlayPanelDensity(
        panelPadding: 9,
        topPadding: 12,
        headerRowsSpacing: 8,
        rowSpacing: 4,
        footerSpacing: 8,
        placesFooterInlineWithLastRow: false,
        bottomClearance: 12
    )
    static let compactDensity = AppKitComposerOverlayPanelDensity(
        panelPadding: 6,
        topPadding: 8,
        headerRowsSpacing: 4,
        rowSpacing: 0,
        footerSpacing: 5,
        placesFooterInlineWithLastRow: true,
        bottomClearance: 12
    )
    static let footerButtonSpacing: CGFloat = 8
    static let buttonHeight: CGFloat = 30
    static let navigationButtonSize: CGFloat = 24
    static let optionPadding: CGFloat = 14
    static let optionVerticalPadding: CGFloat = 10
    static let optionMinimumHeight: CGFloat = 42
    static let compactOptionFontSize: CGFloat = 11.5
    static let compactOptionFontWeight: NSFont.Weight = .regular
    static let compactOptionMinimumHeight: CGFloat = 34
    static let compactOptionVerticalPadding: CGFloat = 5
    static let optionCornerRadius: CGFloat = 8
    static let descriptionSpacing: CGFloat = 3
    static let accessorySpacing: CGFloat = 8
    static let inlineInfoSpacing: CGFloat = 6
    static let infoButtonSize: CGFloat = 18
    static let customFieldHeight: CGFloat = 30
    static let compactCustomFieldHeight: CGFloat = 24
    static let chipHeight: CGFloat = 20
}

@MainActor
struct AppKitComposerOverlayPanelDensity: Equatable {
    let panelPadding: CGFloat
    let topPadding: CGFloat
    let headerRowsSpacing: CGFloat
    let rowSpacing: CGFloat
    let footerSpacing: CGFloat
    let placesFooterInlineWithLastRow: Bool
    let bottomClearance: CGFloat

    nonisolated init(
        panelPadding: CGFloat,
        headerRowsSpacing: CGFloat,
        rowSpacing: CGFloat,
        footerSpacing: CGFloat,
        placesFooterInlineWithLastRow: Bool,
        bottomClearance: CGFloat
    ) {
        self.init(
            panelPadding: panelPadding,
            topPadding: panelPadding,
            headerRowsSpacing: headerRowsSpacing,
            rowSpacing: rowSpacing,
            footerSpacing: footerSpacing,
            placesFooterInlineWithLastRow: placesFooterInlineWithLastRow,
            bottomClearance: bottomClearance
        )
    }

    nonisolated init(
        panelPadding: CGFloat,
        topPadding: CGFloat,
        headerRowsSpacing: CGFloat,
        rowSpacing: CGFloat,
        footerSpacing: CGFloat,
        placesFooterInlineWithLastRow: Bool,
        bottomClearance: CGFloat
    ) {
        self.panelPadding = panelPadding
        self.topPadding = topPadding
        self.headerRowsSpacing = headerRowsSpacing
        self.rowSpacing = rowSpacing
        self.footerSpacing = footerSpacing
        self.placesFooterInlineWithLastRow = placesFooterInlineWithLastRow
        self.bottomClearance = bottomClearance
    }
}

@MainActor
final class AppKitComposerOverlayView: NSView {
    var onPreferredSizeInvalidated: (() -> Void)?

    private let backingView = AppKitFlippedDynamicColorView()
    private let panelView = AppKitComposerOverlayPanelView()
    private var configuration: AppKitComposerOverlayConfiguration?
    private var contentInsets = NSEdgeInsetsZero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(width: bounds.width))
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(width: bounds.width))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard configuration != nil, window != nil else {
            return
        }
        focusFirstOptionAfterLayout()
    }

    func configure(
        _ configuration: AppKitComposerOverlayConfiguration?,
        contentInsets: NSEdgeInsets = NSEdgeInsetsZero
    ) {
        let previousID = self.configuration?.id
        self.configuration = configuration
        self.contentInsets = contentInsets
        guard let configuration else {
            panelView.configure(nil)
            return
        }
        panelView.configure(configuration.panelConfiguration)
        if previousID != configuration.id {
            focusFirstOptionAfterLayout()
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        guard let configuration else {
            return 0
        }
        let contentWidth = max(width - contentInsets.left - contentInsets.right, 0)
        return panelView.measuredHeight(width: contentWidth) + configuration.panelConfiguration.density.bottomClearance
    }

    override func layout() {
        super.layout()
        backingView.frame = bounds
        guard let configuration else {
            panelView.frame = .zero
            return
        }
        let contentWidth = max(bounds.width - contentInsets.left - contentInsets.right, 0)
        let panelHeight = panelView.measuredHeight(width: contentWidth)
        panelView.frame = NSRect(
            x: contentInsets.left,
            y: bounds.height - configuration.panelConfiguration.density.bottomClearance - panelHeight,
            width: contentWidth,
            height: panelHeight
        )
        panelView.layoutSubtreeIfNeeded()
        ensureFocusIfNeeded()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(point) else {
            return nil
        }
        let panelPoint = convert(point, to: panelView)
        if let hit = panelView.hitTest(panelPoint) {
            return hit
        }
        return self
    }

    override func keyDown(with event: NSEvent) {
        if panelView.handleKeyDown(event) {
            return
        }
        // Swallow unhandled keys so they cannot fall through to the composer editor.
    }

    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    func ensureFocusIfNeeded() {
        // Intentionally ignores focus on this root view so a stuck root first
        // responder gets promoted into the first option row; the fallback below
        // keeps key events captured when no row can take focus.
        guard !isHidden,
              window != nil,
              !panelView.containsInteractiveKeyboardFocus else {
            return
        }
        panelView.focusInitialOption()
        if !panelView.containsInteractiveKeyboardFocus {
            window?.makeFirstResponder(self)
        }
    }

    private func setup() {
        wantsLayer = true
        backingView.identifier = NSUserInterfaceItemIdentifier("composer-overlay-backing")
        backingView.wantsLayer = true
        backingView.layer?.backgroundColor = nil
        addSubview(backingView)
        addSubview(panelView)
        panelView.onPreferredSizeInvalidated = { [weak self] in
            self?.invalidateIntrinsicContentSize()
            self?.needsLayout = true
            self?.onPreferredSizeInvalidated?()
        }
    }

    private func focusFirstOptionAfterLayout() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isHidden, self.window != nil else {
                return
            }
            self.layoutSubtreeIfNeeded()
            self.ensureFocusIfNeeded()
        }
    }
}
