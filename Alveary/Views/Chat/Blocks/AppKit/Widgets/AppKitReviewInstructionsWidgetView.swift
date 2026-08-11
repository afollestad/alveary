import AppKit

/// Body for `get_pr_review_instructions`: the user's own review guidance, revealed in place.
///
/// The instructions run to a couple of dozen lines and are the same every time, so the card opens
/// collapsed — the point is that the user can *check* what the agent was told, not read it again
/// on every review. The shell owns the interaction: clicking the card toggles `isExpanded` and the
/// header caret rotates with it, so this body is just the markdown and the expansion flag.
@MainActor
final class AppKitReviewInstructionsWidgetView: NSView {
    struct Configuration: Equatable {
        let content: ReviewInstructionsWidgetContent
        let typography: TranscriptTypography
    }

    /// An inline image landing in the instructions grows the body, which moves everything below.
    var onHeightInvalidated: (() -> Void)?
    var onOpenMarkdownLink: ((URL) -> Void)?

    /// View-local like the pull-request list card's: rows are cached by id, so the disclosure
    /// survives every reconfigure and only different instructions close it again.
    private(set) var isExpanded = false

    private let bodyView = AppKitMarkdownView(document: AppMarkdownDocument(content: AttributedString()))
    private var configuration: Configuration?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.onOpenLink = { [weak self] url in
            self?.onOpenMarkdownLink?(url)
        }
        bodyView.onHeightInvalidated = { [weak self] in
            self?.onHeightInvalidated?()
        }
        addSubview(bodyView)
        NSLayoutConstraint.activate([
            bodyView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyView.topAnchor.constraint(equalTo: topAnchor),
            bodyView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    var hasContent: Bool {
        configuration?.content.hasInstructions == true
    }

    var naturalWidth: CGFloat {
        ceil(bodyView.fittingSize.width)
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        // Different instructions are a different card, so it opens collapsed again; a reconfigure
        // that only changes typography must not fold it up under the user.
        if self.configuration?.content.instructions != configuration.content.instructions {
            isExpanded = false
        }
        self.configuration = configuration
        updateBody(configuration)
    }

    /// Returns the new state so the shell can rotate the caret and republish the row height.
    @discardableResult
    func toggleExpansion() -> Bool {
        isExpanded.toggle()
        return isExpanded
    }
}

private extension AppKitReviewInstructionsWidgetView {
    func updateBody(_ configuration: Configuration) {
        guard let markdown = configuration.content.instructions, configuration.content.hasInstructions else {
            return
        }
        let document = AppMarkdownDocumentCache.document(
            markdown: markdown,
            context: AppMarkdownDocumentCacheContext(
                baseURL: nil,
                inlineCodeStyle: .standard,
                composerChipMode: .none,
                taskStateScope: nil
            )
        ) {
            AppMarkdownParser().documentPreservingSource(for: markdown)
        }
        bodyView.configure(
            document: document,
            inlineCodeStyle: .standard,
            // Scaled down from the chat body size: these are settings the user wrote once, shown
            // for reference, not prose to read at full size.
            typography: Self.bodyTypography(configuration.typography)
        )
    }

    static func bodyTypography(_ typography: TranscriptTypography) -> AppKitMarkdownTypography {
        AppKitMarkdownTypography(
            title1: typography.nsFont(.headline, weight: .semibold),
            title2: typography.nsFont(.headline, weight: .semibold),
            headline: typography.nsFont(.body, weight: .semibold),
            subheadline: typography.nsFont(.toolSummary, weight: .semibold),
            body: typography.nsFont(.toolSummary),
            codeBlock: typography.inlineToolCodeNSFont,
            inlineCode: typography.inlineToolCodeNSFont
        )
    }
}
