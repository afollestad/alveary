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

/// Drops one staged comment from the review before it is submitted.
///
/// The one control a proposal comment card carries. It edits the stored envelope and nothing else,
/// which is what keeps it inside the card's premise that nothing reaches GitHub before confirmation.
/// Built on `AppKitHostToolWidgetBubbleView` for the transcript's press, cursor, button role, and
/// hover — including the scroll-under-pointer re-derivation a scrolling transcript needs.
///
/// Removal takes two presses, like the sidebar's archive/delete pill: the first swaps the glyph for
/// a red `Confirm`, and only the second removes. A staged comment is the review's substance and
/// there is no undo, so a mis-click must not silently drop one.
@MainActor
final class AppKitReviewProposalCommentRemoveButton: AppKitHostToolWidgetBubbleView {
    /// The hover circle, wider than the glyph needs so the fill has room around it.
    static let diameter: CGFloat = 24
    /// What the author row lays the button out by. Auto Layout positions a view by its alignment
    /// rect, so keeping that at the glyph's own box lets the circle grow outward without moving the
    /// glyph or heightening the row — and the overflow still takes clicks, hover, and the cursor,
    /// because those read `bounds`.
    static let alignmentDiameter: CGFloat = 16
    /// How long an armed pill waits once the pointer has left. Matching the sidebar's, and for the
    /// same reason: a user still deciding is hovering, so the countdown never runs under them.
    static let confirmationTimeoutNanoseconds: UInt64 = 500_000_000
    private static let titleHorizontalPadding: CGFloat = 8
    /// `ActionButtonTint.destructive`, the app's one destructive fill.
    private static let destructiveTint = NSColor(ActionButtonTint.destructive)

    /// The second press. The first only arms the pill.
    var onConfirm: (() -> Void)?

    private let glyphView = AppKitDynamicTintImageView()
    private let titleField = NSTextField(labelWithString: "Confirm")
    private var widthConstraint: NSLayoutConstraint?
    private var disarmTask: Task<Void, Never>?
    private var isArmed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Self.diameter / 2
        isInteractive = true
        onHoverChanged = { [weak self] _ in
            self?.applyState()
        }
        onActivate = { [weak self] in
            self?.handlePress()
        }
        setupContent()
        applyState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: alignmentWidth, height: Self.alignmentDiameter)
    }

    override var alignmentRectInsets: NSEdgeInsets {
        let inset = (Self.diameter - Self.alignmentDiameter) / 2
        return NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
    }

    /// Regular weight at the author row's own size: at semibold the glyph out-shouted the caption
    /// text it sits beside and read as a second Cancel.
    func configure(fontSize: CGFloat) {
        glyphView.symbolConfiguration = .init(pointSize: fontSize, weight: .regular)
        titleField.font = .systemFont(ofSize: fontSize, weight: .semibold)
        // A reconfigure means the card is showing different content, so a pill armed against the
        // old one must not carry over.
        disarm()
    }

    /// Cancelled here rather than in `deinit`, which cannot touch main-actor state.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil else {
            return
        }
        disarm()
    }
}

private extension AppKitReviewProposalCommentRemoveButton {
    var alignmentWidth: CGFloat {
        guard isArmed else {
            return Self.alignmentDiameter
        }
        let title = ceil(titleField.attributedStringValue.size().width)
        return title + (Self.titleHorizontalPadding * 2)
    }

    func handlePress() {
        guard isArmed else {
            isArmed = true
            applyState()
            return
        }
        disarm()
        onConfirm?()
    }

    func disarm() {
        disarmTask?.cancel()
        disarmTask = nil
        guard isArmed else {
            return
        }
        isArmed = false
        applyState()
    }

    /// Both the pill's appearance and its countdown follow from armed plus hovered, so one place
    /// derives them — a hover change while armed is exactly what starts and stops the clock.
    func applyState() {
        glyphView.isHidden = isArmed
        titleField.isHidden = !isArmed
        if isArmed {
            setLayerFillColor(Self.destructiveTint, alpha: 1)
        } else {
            setLayerFillColor(.secondaryLabelColor, alpha: isHovered ? 0.16 : 0)
        }
        setAccessibilityLabel(isArmed ? "Confirm removing this proposed comment" : "Remove proposed comment")
        toolTip = isArmed ? "Press again to remove this comment" : "Remove this comment from the review"
        widthConstraint?.constant = alignmentWidth
        invalidateIntrinsicContentSize()
        scheduleDisarmIfNeeded()
    }

    func scheduleDisarmIfNeeded() {
        disarmTask?.cancel()
        disarmTask = nil
        guard isArmed, !isHovered else {
            return
        }
        disarmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.confirmationTimeoutNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            self?.disarm()
        }
    }

    func setupContent() {
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.setAccessibilityElement(false)
        glyphView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        glyphView.setDynamicContentTintColor(.secondaryLabelColor)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.setAccessibilityElement(false)
        titleField.textColor = .white
        titleField.maximumNumberOfLines = 1
        addSubview(glyphView)
        addSubview(titleField)
        let width = widthAnchor.constraint(equalToConstant: Self.alignmentDiameter)
        widthConstraint = width
        // Sized and centred against the alignment rect, which the symmetric insets keep concentric
        // with the frame — so the glyph lands where it did before the circle grew.
        NSLayoutConstraint.activate([
            width,
            heightAnchor.constraint(equalToConstant: Self.alignmentDiameter),
            glyphView.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
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
