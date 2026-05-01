@preconcurrency import AppKit
import Foundation

// AppKit transcript rows use this renderer to make markdown height changes
// explicit; SwiftUI lazy-list measurement was not reliable enough for this UX.
final class AppKitMarkdownView: NSView {
    var onHeightInvalidated: (() -> Void)?
    var onOpenLink: ((URL) -> Void)? {
        didSet {
            applyLinkHandler(to: self)
        }
    }

    private let stackView = NSStackView()
    private var document: AppMarkdownDocument
    private var inlineCodeStyle: AppMarkdownInlineCodeStyle
    private var typography: AppKitMarkdownTypography

    init(
        document: AppMarkdownDocument,
        inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard,
        typography: AppKitMarkdownTypography = .default,
        onOpenLink: ((URL) -> Void)? = nil
    ) {
        self.document = document
        self.inlineCodeStyle = inlineCodeStyle
        self.typography = typography
        self.onOpenLink = onOpenLink
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

    func configure(
        document: AppMarkdownDocument,
        inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard,
        typography: AppKitMarkdownTypography = .default
    ) {
        guard self.document != document || self.inlineCodeStyle != inlineCodeStyle || self.typography != typography else {
            return
        }
        self.document = document
        self.inlineCodeStyle = inlineCodeStyle
        self.typography = typography
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
            onOpenLink: onOpenLink,
            heightInvalidationHandler: { [weak self] in
                self?.invalidateMarkdownHeight()
            }
        )
        renderer.views(for: document.content).forEach(stackView.addArrangedSubview)
        invalidateMarkdownHeight()
    }

    private func applyLinkHandler(to view: NSView) {
        if let textView = view as? AppKitMarkdownTextView {
            textView.onOpenLink = onOpenLink
        }
        view.subviews.forEach(applyLinkHandler(to:))
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
