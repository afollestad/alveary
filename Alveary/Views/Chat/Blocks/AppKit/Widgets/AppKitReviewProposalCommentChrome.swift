import AppKit
import SwiftUI

/// The circular author avatar a pull-request comment leads with, in AppKit.
///
/// Mirrors `PullRequestAvatarView`: a `secondary @ 0.2` disc sits behind the image so a bot's
/// transparent glyph stays legible on both themes, and the author's initial stands in until the
/// image arrives. Decorative — the adjacent author label carries the name.
@MainActor
final class AppKitPullRequestAvatarView: NSView {
    static let diameter: CGFloat = 16

    private let imageView = NSImageView()
    private let initialField = NSTextField(labelWithString: "")
    private var loadTask: Task<Void, Never>?
    private var loadedURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Self.diameter / 2
        layer?.masksToBounds = true
        setupSubviews()
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.diameter, height: Self.diameter)
    }

    /// Reconfiguring with the same URL keeps the loaded image, because the transcript rebuilds this
    /// card on every unrelated proposal change and a re-fetch would blink the avatar back to its
    /// initial each time.
    func configure(login: String, url: URL?, loader: GitHubAvatarLoader?) {
        initialField.stringValue = String(login.prefix(1)).uppercased()
        guard url != loadedURL || (url != nil && imageView.image == nil) else {
            return
        }
        loadedURL = url
        loadTask?.cancel()
        loadTask = nil
        imageView.image = nil
        initialField.isHidden = false
        guard let url, let loader else {
            return
        }
        loadTask = Task { [weak self] in
            let image = await loader.image(for: url)
            guard !Task.isCancelled, let self, loadedURL == url, let image else {
                return
            }
            imageView.image = image
            initialField.isHidden = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: 0.2).setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A tinted capsule pill beside an author row, mirroring `PullRequestCommentBadge`. The review
/// card only ever draws `Pending`, but the shape is the pane's so the two surfaces read alike.
@MainActor
final class AppKitPullRequestCommentBadgeView: NSView {
    enum Style: Equatable {
        /// A filled pill in the given tint, at the pane's 0.14 fill alpha.
        case tinted(NSColor)
        /// The `Bot` pill: no fill, a hairline capsule, secondary text.
        case outlined
    }

    private static let horizontalPadding: CGFloat = 6
    private static let verticalPadding: CGFloat = 2

    private let titleField = NSTextField(labelWithString: "")
    private var style = Style.outlined

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.maximumNumberOfLines = 1
        addSubview(titleField)
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            titleField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    func configure(title: String, style: Style, fontSize: CGFloat) {
        self.style = style
        titleField.stringValue = title
        switch style {
        case .tinted(let tint):
            titleField.font = .systemFont(ofSize: fontSize, weight: .semibold)
            titleField.textColor = tint
        case .outlined:
            titleField.font = .systemFont(ofSize: fontSize)
            titleField.textColor = .secondaryLabelColor
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Inset by half the stroke so an outlined capsule's hairline lands inside the bounds the
        // stack measured, rather than being clipped to half its width.
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        switch style {
        case .tinted(let tint):
            tint.appKitResolvedColor(in: self, alpha: 0.14).setFill()
            path.fill()
        case .outlined:
            NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: 0.4).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The comment card's three-dot menu, holding the one action a staged comment has.
///
/// Mirrors the pane's `PullRequestCommentActionsMenu`: the same `ellipsis` glyph, the same hit
/// target — which is also the hover circle, so the glyph centers in it — the same "Comment actions"
/// name, and one destructive row. Deleting asks for no confirmation, exactly as it does not in the
/// pane — a staged comment exists only in the stored envelope, so dropping it publishes nothing.
///
/// Built on `AppKitHostToolWidgetBubbleView` for the transcript's press, cursor, and button role.
@MainActor
final class AppKitReviewProposalCommentMenuButton: AppKitHostToolWidgetBubbleView {
    var onDelete: (() -> Void)?

    private let glyphView = AppKitDynamicTintImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        isInteractive = true
        onActivate = { [weak self] in
            self?.presentMenu()
        }
        setupContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        PullRequestCommentActionsMenu.hitTargetSize
    }

    /// Drawn rather than layered: `draw(_:)` resolves the fill against the live
    /// appearance, while a `CALayer` background would need its own theme observer.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovered else {
            return
        }

        // The pane's fill is `Color.secondary.opacity(0.16)`, which *multiplies* the
        // label colour's own alpha rather than replacing it. Matching that keeps the
        // two circles the same weight; setting 0.16 outright renders twice as dark.
        let base = NSColor.secondaryLabelColor.usingColorSpace(.sRGB) ?? .secondaryLabelColor
        base.withAlphaComponent(base.alphaComponent * 0.16).setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    /// The pane draws its ellipsis at a fixed size beside `.caption` text; the transcript's caption
    /// follows the chat font-size setting, so this one tracks that instead of freezing.
    func configure(fontSize: CGFloat) {
        glyphView.symbolConfiguration = .init(pointSize: fontSize, weight: .semibold)
    }

    /// The menu the button pops, built separately so tests can run its row: `NSMenu.popUp` enters a
    /// modal tracking loop, which a test cannot drive.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let delete = NSMenuItem(
            title: PullRequestCommentActionsMenu.deleteTitle,
            action: #selector(handleDelete),
            keyEquivalent: ""
        )
        delete.target = self
        delete.image = NSImage(
            systemSymbolName: PullRequestCommentActionsMenu.deleteSymbolName,
            accessibilityDescription: nil
        )
        menu.addItem(delete)
        return menu
    }
}

private extension AppKitReviewProposalCommentMenuButton {
    func setupContent() {
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.setAccessibilityElement(false)
        glyphView.image = NSImage(
            systemSymbolName: PullRequestCommentActionsMenu.glyphSymbolName,
            accessibilityDescription: nil
        )
        glyphView.setDynamicContentTintColor(.secondaryLabelColor)
        addSubview(glyphView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: PullRequestCommentActionsMenu.hitTargetSize.width),
            heightAnchor.constraint(equalToConstant: PullRequestCommentActionsMenu.hitTargetSize.height),
            // Centered, matching the pane now that the hit target is the hover
            // circle rather than a wider lane the glyph hugged the end of.
            glyphView.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        // The bubble tracks hover but draws nothing; this is the pane's hover
        // circle, so the same control reads the same way on both surfaces.
        onHoverChanged = { [weak self] _ in
            self?.needsDisplay = true
        }
        setAccessibilityLabel(PullRequestCommentActionsMenu.name)
        toolTip = PullRequestCommentActionsMenu.name
    }

    func presentMenu() {
        // The view is flipped, so its maximum Y edge is the bottom — the menu drops below the
        // glyph the way the pane's does.
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 2), in: self)
    }

    @objc func handleDelete() {
        onDelete?()
    }
}

/// Opens this comment in the pull request pane's Changes tab, scrolled to the line it annotates.
///
/// An accent icon-and-text button matching the pane's own "Show in Changes" — same
/// `Octicon.fileDiff16`, same accent, same caption type, and the same brightening on hover —
/// because the two are one affordance seen from two surfaces. Single press: it navigates rather
/// than destroys.
///
/// `alphaValue` is what carries the hover, because it is the one lever that reaches both halves at
/// once: the label is a dynamic colour the field re-resolves itself, while the octicon's tint is
/// baked into a bitmap. Set unanimated, like the hover circle on the menu button beside it, and
/// re-derived when the system's accessibility display options change so Increase Contrast can drop
/// the resting fade mid-session.
@MainActor
final class AppKitReviewProposalCommentJumpButton: AppKitHostToolWidgetBubbleView {
    var onJump: (() -> Void)?

    /// Injected so tests can pin both contrast branches; production reads the live system setting.
    var increasesContrast: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast } {
        didSet {
            refreshHoverAlpha()
        }
    }

    private var accessibilityDisplayOptionsObserver: NSObjectProtocol?

    private let glyphView = NSImageView()
    private let titleField = NSTextField(labelWithString: PullRequestCommentRevealAction.transcriptTitle)
    /// Held because an octicon's tint is baked into the rendered image, so an appearance change
    /// has to redraw it — unlike an SF Symbol, which `AppKitDynamicTintImageView` can retint.
    private var glyphSide = ActionButtonMetrics.inlineOcticonGlyphSize
    private var glyphWidthConstraint: NSLayoutConstraint?
    private var glyphHeightConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        isInteractive = true
        onActivate = { [weak self] in
            self?.onJump?()
        }
        setupContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let accessibilityDisplayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityDisplayOptionsObserver)
        }
    }

    /// Internal so `ReviewProposalCommentControlsTests` can re-derive after injecting a contrast
    /// value; every production caller is in this file.
    func refreshHoverAlpha() {
        alphaValue = isHovered
            ? InlineActionButtonOpacity.active
            : InlineActionButtonOpacity.resting(increasesContrast: increasesContrast())
    }

    /// Octicon artwork under-fills its canvas, which is why the pane's shared
    /// `ActionButtonMetrics.inlineOcticonGlyphSize` sits two points above the `.caption` text it is
    /// paired with rather than matching it. The transcript's caption follows the chat font-size
    /// setting, so the glyph box keeps that same offset instead of freezing at the pane's number.
    func configure(fontSize: CGFloat) {
        titleField.font = .systemFont(ofSize: fontSize)
        glyphSide = fontSize + Self.glyphSizeOffset
        glyphWidthConstraint?.constant = glyphSide
        glyphHeightConstraint?.constant = glyphSide
        renderGlyph()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderGlyph()
    }
}

private extension AppKitReviewProposalCommentJumpButton {
    /// How far the pane's inline glyph box sits above the `.caption` size it accompanies.
    static let glyphSizeOffset = ActionButtonMetrics.inlineOcticonGlyphSize - 10

    func setupContent() {
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.setAccessibilityElement(false)
        glyphView.imageScaling = .scaleProportionallyUpOrDown
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.setAccessibilityElement(false)
        titleField.maximumNumberOfLines = 1
        titleField.lineBreakMode = .byTruncatingTail
        // A dynamic colour, so the field re-resolves it across appearances by itself; only the
        // octicon, whose tint is baked into the rendered bitmap, has to be redrawn.
        titleField.textColor = PullRequestCommentRevealAction.tintNSColor
        addSubview(glyphView)
        addSubview(titleField)
        let glyphWidth = glyphView.widthAnchor.constraint(equalToConstant: glyphSide)
        let glyphHeight = glyphView.heightAnchor.constraint(equalToConstant: glyphSide)
        glyphWidthConstraint = glyphWidth
        glyphHeightConstraint = glyphHeight
        NSLayoutConstraint.activate([
            glyphWidth,
            glyphHeight,
            glyphView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glyphView.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.leadingAnchor.constraint(
                equalTo: glyphView.trailingAnchor,
                constant: ActionButtonMetrics.inlineIconLabelSpacing
            ),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleField.topAnchor.constraint(equalTo: topAnchor),
            titleField.bottomAnchor.constraint(equalTo: bottomAnchor),
            // The glyph box outgrows the label's line height at the smallest chat font sizes;
            // without this the artwork would overhang the author row.
            heightAnchor.constraint(greaterThanOrEqualTo: glyphView.heightAnchor)
        ])
        refreshHoverAlpha()
        onHoverChanged = { [weak self] _ in
            self?.refreshHoverAlpha()
        }
        accessibilityDisplayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshHoverAlpha()
            }
        }
        setAccessibilityLabel(PullRequestCommentRevealAction.transcriptName)
        toolTip = PullRequestCommentRevealAction.transcriptName
    }

    func renderGlyph() {
        let color = PullRequestCommentRevealAction.tintNSColor.appKitResolvedColor(in: self, alpha: 1)
        glyphView.image = PullRequestCommentRevealAction.icon.nsImage(side: glyphSide, color: color)
    }
}

extension AppKitPullRequestCommentBadgeView {
    /// The pane's orange, taken from the SwiftUI token rather than `.systemOrange` so the pill
    /// matches `PullRequestCommentBadge("Pending", color: .orange)` exactly.
    static let pendingTint = NSColor(Color.orange)
}

private extension AppKitPullRequestAvatarView {
    func setupSubviews() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        initialField.translatesAutoresizingMaskIntoConstraints = false
        initialField.alignment = .center
        initialField.textColor = .secondaryLabelColor
        initialField.font = .systemFont(ofSize: Self.diameter * 0.55, weight: .semibold)
        addSubview(initialField)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            initialField.centerXAnchor.constraint(equalTo: centerXAnchor),
            initialField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
