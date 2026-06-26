@preconcurrency import AppKit
import BlockInputKit
import Foundation

// AppKit transcript rows use this renderer to make markdown height changes
// explicit; SwiftUI lazy-list measurement was not reliable enough for this UX.
final class AppKitMarkdownView: NSView {
    var onHeightInvalidated: (() -> Void)?
    var maximumImageDisplayWidth: CGFloat? {
        didSet {
            guard oldValue != maximumImageDisplayWidth else {
                return
            }
            updateImageDisplayWidths()
        }
    }
    var onOpenLink: ((URL) -> Void)? {
        didSet {
            applyLinkHandler(to: self)
        }
    }
    var onOpenImage: ((BlockInputImage, URL?) -> Void)? {
        didSet {
            applyImageOpenHandler(to: self)
        }
    }

    private let stackView = NSStackView()
    private var document: AppMarkdownDocument
    private var inlineCodeStyle: AppMarkdownInlineCodeStyle
    private var typography: AppKitMarkdownTypography
    private var imageBaseURL: URL?

    init(
        document: AppMarkdownDocument,
        inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard,
        typography: AppKitMarkdownTypography = .default,
        imageBaseURL: URL? = nil,
        onOpenLink: ((URL) -> Void)? = nil,
        onOpenImage: ((BlockInputImage, URL?) -> Void)? = nil
    ) {
        self.document = document
        self.inlineCodeStyle = inlineCodeStyle
        self.typography = typography
        self.imageBaseURL = imageBaseURL
        self.onOpenLink = onOpenLink
        self.onOpenImage = onOpenImage
        super.init(frame: .zero)
        setup()
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        let fittingSize = stackView.fittingSize
        return NSSize(width: NSView.noIntrinsicMetric, height: fittingSize.height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateImageDisplayWidths()
    }

    override func layout() {
        updateImageDisplayWidths()
        super.layout()
    }

    func configure(
        document: AppMarkdownDocument,
        inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard,
        typography: AppKitMarkdownTypography = .default,
        imageBaseURL: URL? = nil
    ) {
        guard self.document != document ||
            self.inlineCodeStyle != inlineCodeStyle ||
            self.typography != typography ||
            self.imageBaseURL != imageBaseURL else {
            return
        }
        self.document = document
        self.inlineCodeStyle = inlineCodeStyle
        self.typography = typography
        self.imageBaseURL = imageBaseURL
        rebuild()
    }

    func invalidateMarkdownHeight() {
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = AppKitMarkdownMetrics.blockSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            // Transcript rows temporarily probe markdown with larger frames while
            // measuring. Keep the stack at its natural height so tables and code
            // blocks do not stretch just because the probe frame is tall.
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    private func rebuild() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let renderer = AppKitMarkdownBlockRenderer(
            taskStateNamespace: document.taskStateNamespace,
            inlineCodeStyle: inlineCodeStyle,
            typography: typography,
            imageBaseURL: imageBaseURL,
            onOpenLink: onOpenLink,
            onOpenImage: onOpenImage,
            heightInvalidationHandler: { [weak self] in
                self?.invalidateMarkdownHeight()
            }
        )
        renderer.views(for: document.blocks).forEach { view in
            stackView.addArrangedSubview(view)
            // Image blocks hug their display size instead of stretching to the
            // stack width, which leaves their horizontal position ambiguous;
            // AppKit resolves that to the trailing edge, so pin them leading.
            if view is AppKitMarkdownImageBlockView {
                view.leadingAnchor.constraint(equalTo: stackView.leadingAnchor).isActive = true
            }
        }
        updateImageDisplayWidths()
        invalidateMarkdownHeight()
    }

    private func applyLinkHandler(to view: NSView) {
        if let textView = view as? AppKitMarkdownTextView {
            textView.onOpenLink = onOpenLink
        }
        view.subviews.forEach(applyLinkHandler(to:))
    }

    private func applyImageOpenHandler(to view: NSView) {
        if let imageView = view as? AppKitMarkdownImageBlockView {
            imageView.onOpen = onOpenImage
        }
        view.subviews.forEach(applyImageOpenHandler(to:))
    }

    private func updateImageDisplayWidths() {
        let viewWidth = bounds.width > 0 ? bounds.width : AppKitMarkdownImageBlockView.defaultInitialWidth
        let width = maximumImageDisplayWidth.map { min(viewWidth, max($0, 0)) } ?? viewWidth
        appKitMarkdownImageViews(in: self).forEach { imageView in
            imageView.maximumDisplayWidth = width
        }
    }

    private func appKitMarkdownImageViews(in view: NSView) -> [AppKitMarkdownImageBlockView] {
        view.subviews.flatMap { child -> [AppKitMarkdownImageBlockView] in
            var matches = appKitMarkdownImageViews(in: child)
            if let imageView = child as? AppKitMarkdownImageBlockView {
                matches.insert(imageView, at: 0)
            }
            return matches
        }
    }
}

enum AppKitMarkdownMetrics {
    static let blockSpacing: CGFloat = 8
    static let listItemSpacing: CGFloat = 5
    static let orderedListMarkerWidth: CGFloat = 32
    static let unorderedListMarkerWidth: CGFloat = 32
    static let unorderedBulletDiameterScale: CGFloat = 0.36
    static let unorderedBulletLeadingInset: CGFloat = 18
    static let taskMarkerWidth: CGFloat = 18
    static let quoteBarWidth: CGFloat = 3
    static let codeCornerRadius: CGFloat = 8
}
