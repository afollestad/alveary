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
