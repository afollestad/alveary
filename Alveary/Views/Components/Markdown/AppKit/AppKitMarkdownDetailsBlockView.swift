@preconcurrency import AppKit
import QuartzCore

/// AppKit counterpart to `AppMarkdownDetailsBlockView`: a GitHub `<details>` disclosure.
///
/// The body is built lazily and *removed* from the stack when collapsed rather than hidden at zero
/// height, because `NSStackView` spends its spacing around any arranged subview it still considers
/// laid out — a collapsed disclosure would otherwise carry a block's worth of gap beneath it, and
/// `AppKitMarkdownView` sizes itself straight off `stackView.fittingSize`.
@MainActor
final class AppKitMarkdownDetailsBlockView: NSView {
    private let stackView = NSStackView()
    private let headerView: AppKitMarkdownDetailsHeaderView
    private let bodyContainer = NSView()
    private let makeContentViews: @MainActor () -> [NSView]
    private let storeID: String
    private let onHeightInvalidated: () -> Void

    private var isExpanded: Bool
    private var hasBuiltBody = false

    init(
        summary: NSAttributedString,
        accessibilityLabel: String,
        hasBody: Bool,
        storeID: String,
        isInitiallyOpen: Bool,
        makeContentViews: @MainActor @escaping () -> [NSView],
        onHeightInvalidated: @escaping () -> Void
    ) {
        self.makeContentViews = makeContentViews
        self.storeID = storeID
        self.onHeightInvalidated = onHeightInvalidated
        isExpanded = AppMarkdownDetailsExpansionStore.value(for: storeID, defaultValue: isInitiallyOpen)
        headerView = AppKitMarkdownDetailsHeaderView(
            summary: summary,
            accessibilityLabel: accessibilityLabel,
            onHeightInvalidated: onHeightInvalidated
        )
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        // `.width` pins each arranged subview to the stack's width as it is added, which is what
        // the header and body both need; an explicit width constraint cannot be activated here
        // because neither is in the hierarchy yet.
        stackView.alignment = .width
        // Zero, so the header/body gap is the body container's own top inset and disappears with
        // it. See the type's note on `NSStackView` spacing.
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        headerView.onToggle = { [weak self] in
            self?.toggle()
        }
        stackView.addArrangedSubview(headerView)
        headerView.setExpanded(isExpanded, animated: false)
        // A disclosure with no body is still a disclosure; it just has nothing to reveal.
        if hasBody {
            applyExpansion()
        } else {
            headerView.isEnabled = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    private func toggle() {
        isExpanded.toggle()
        AppMarkdownDetailsExpansionStore.set(isExpanded, for: storeID)
        headerView.setExpanded(isExpanded, animated: true)
        applyExpansion()
        invalidateIntrinsicContentSize()
        needsLayout = true
        // The transcript measures a row from its content, so a disclosure that grew or shrank
        // without saying so leaves every row below it at the old offset.
        onHeightInvalidated()
    }

    private func applyExpansion() {
        guard isExpanded else {
            if bodyContainer.superview != nil {
                stackView.removeArrangedSubview(bodyContainer)
                bodyContainer.removeFromSuperview()
            }
            return
        }

        buildBodyIfNeeded()
        guard bodyContainer.superview == nil else {
            return
        }
        stackView.addArrangedSubview(bodyContainer)
    }

    /// Deferred until the first expansion: a collapsed disclosure is usually hiding something
    /// expensive — a long log, a wide table — and building it to keep it off screen is the cost
    /// the disclosure exists to avoid.
    private func buildBodyIfNeeded() {
        guard !hasBuiltBody else {
            return
        }
        hasBuiltBody = true

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = AppKitMarkdownMetrics.blockSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        makeContentViews().forEach(contentStack.addArrangedSubview)

        bodyContainer.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(
                equalTo: bodyContainer.topAnchor,
                constant: AppMarkdownDetailsMetrics.bodySpacing
            ),
            contentStack.leadingAnchor.constraint(
                equalTo: bodyContainer.leadingAnchor,
                constant: AppMarkdownDetailsMetrics.bodyIndent
            ),
            contentStack.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor)
        ])
    }
}

/// The clickable summary row: a rotating chevron beside the summary text.
///
/// The summary is an `AppKitMarkdownTextView` and not an `NSTextField` so it wraps through the
/// same `NSLayoutManager` the measurer uses — a field's own cell sizing would put the drawn header
/// a point or two off the measured one, which the transcript would show as a sliver of dead space
/// under every disclosure. Selection is off, and `hitTest` funnels every press in the row to the
/// toggle, because a selectable text view otherwise eats the click.
@MainActor
final class AppKitMarkdownDetailsHeaderView: NSView {
    var onToggle: (() -> Void)?
    var isEnabled = true {
        didSet {
            alphaValue = isEnabled ? 1 : AppMarkdownDetailsMetrics.inertHeaderOpacity
        }
    }

    private let chevronView = NSImageView()
    private let summaryView: AppKitMarkdownTextView
    private let firstLineHeight: CGFloat
    private var isExpanded = false
    private var isPressed = false {
        didSet {
            alphaValue = isPressed ? appHeaderTogglePressedOpacity : 1
        }
    }

    init(
        summary: NSAttributedString,
        accessibilityLabel: String,
        onHeightInvalidated: @escaping () -> Void
    ) {
        // No `onOpenLink`: the header takes every click as the toggle, so a link inside a summary
        // could never receive one. GitHub's own summaries read as toggles first, and wiring a
        // handler that cannot fire would only look like it worked.
        summaryView = AppKitMarkdownTextView(
            content: summary,
            heightInvalidationHandler: onHeightInvalidated
        )
        firstLineHeight = AppKitMarkdownDetailsHeaderView.lineHeight(of: summary)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        chevronView.translatesAutoresizingMaskIntoConstraints = true
        chevronView.wantsLayer = true
        chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevronView.symbolConfiguration = .init(
            pointSize: AppMarkdownDetailsMetrics.chevronWidth * 0.72,
            weight: .semibold
        )
        chevronView.contentTintColor = .tertiaryLabelColor
        chevronView.setAccessibilityElement(false)
        addSubview(chevronView)

        summaryView.isSelectable = false
        summaryView.setAccessibilityElement(false)
        addSubview(summaryView)

        NSLayoutConstraint.activate([
            // Equal, not `lessThanOrEqual`: the measurer wraps the summary at exactly
            // `width - chevronWidth - chevronSpacing`, so the drawn view has to take that width.
            summaryView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: AppMarkdownDetailsMetrics.chevronWidth + AppMarkdownDetailsMetrics.chevronSpacing
            ),
            summaryView.trailingAnchor.constraint(equalTo: trailingAnchor),
            summaryView.topAnchor.constraint(equalTo: topAnchor),
            summaryView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.disclosureTriangle)
        setAccessibilityLabel(accessibilityLabel)
        updateAccessibilityValue()
    }

    /// Centers the chevron on the summary's first line rather than on the whole header, so a
    /// summary that wraps to two lines does not drop the glyph into the gap between them.
    private static func lineHeight(of summary: NSAttributedString) -> CGFloat {
        let font = summary.length > 0
            ? summary.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            : nil
        return NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.systemFontSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        let size = min(AppMarkdownDetailsMetrics.chevronWidth, bounds.height)
        chevronView.frame = NSRect(
            x: 0,
            y: max((firstLineHeight - size) / 2, 0),
            width: AppMarkdownDetailsMetrics.chevronWidth,
            height: size
        )
        positionChevronLayer()
    }

    /// Every click in the header is the toggle; without this the summary label takes it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else {
            return nil
        }
        return super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        isPressed = false
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return
        }
        onToggle?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else {
            return false
        }
        onToggle?()
        return true
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard isExpanded != expanded else {
            return
        }
        let previousRotation = rotation
        isExpanded = expanded
        updateAccessibilityValue()
        positionChevronLayer()
        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = chevronView.layer else {
            return
        }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = previousRotation
        animation.toValue = rotation
        animation.duration = 0.16
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "markdownDetailsDisclosureRotation")
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue(isExpanded ? "expanded" : "collapsed")
    }

    private var rotation: CGFloat {
        // Positive because this view is flipped, which inverts a layer rotation's visual
        // direction; the caret has to point down when open.
        isExpanded ? CGFloat.pi / 2 : 0
    }

    private func positionChevronLayer() {
        guard let layer = chevronView.layer else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.bounds = CGRect(origin: .zero, size: chevronView.bounds.size)
        layer.position = CGPoint(x: chevronView.frame.midX, y: chevronView.frame.midY)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: rotation))
        CATransaction.commit()
    }
}
