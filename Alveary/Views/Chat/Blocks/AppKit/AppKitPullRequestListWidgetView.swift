import AppKit

/// Body for `list_involved_prs`: one row per pull request, each opening its own.
///
/// The only read-only host tool with a card. A lookup that just reports keeps the ordinary tool
/// row, but every row here is a separate destination, so the list needs the block-level chrome —
/// and the card itself is inert, since there is no single pull request for it to open.
@MainActor
final class AppKitPullRequestListWidgetView: NSView {
    struct Configuration: Equatable {
        let content: PullRequestListWidgetContent
        let typography: TranscriptTypography
    }

    var onOpenPullRequest: ((PullRequestIdentifier) -> Void)?
    /// Expanding adds rows, which changes the transcript row's measured height.
    var onHeightInvalidated: (() -> Void)?

    /// A long list would otherwise push the rest of the turn off screen, so the card opens at a
    /// readable size and grows in place.
    static let collapsedRowLimit = 8

    private let stack = NSStackView()
    private var configuration: Configuration?
    private var isExpanded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
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
        !stack.arrangedSubviews.isEmpty
    }

    var naturalWidth: CGFloat {
        stack.arrangedSubviews.reduce(CGFloat.zero) { widest, row in
            max(widest, ceil(row.fittingSize.width))
        }
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        // A different list is a different question, so it opens collapsed again; a reconfigure
        // that only changes typography must not fold the list back up under the user.
        if self.configuration?.content != configuration.content {
            isExpanded = false
        }
        self.configuration = configuration
        rebuild(configuration)
    }
}

private extension AppKitPullRequestListWidgetView {
    static let rowVerticalPadding: CGFloat = 6
    static let iconSpacing: CGFloat = 8
    /// How far the hover surface extends past the row's content on each side.
    static let highlightOutset: CGFloat = 6

    func rebuild(_ configuration: Configuration) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let allRows = configuration.content.rows
        let visible = isExpanded ? allRows : Array(allRows.prefix(Self.collapsedRowLimit))
        for (index, row) in visible.enumerated() {
            if index > 0 {
                stack.addFullWidthArrangedSubview(divider())
            }
            stack.addFullWidthArrangedSubview(rowView(row, configuration: configuration))
        }
        // The toggle stays once the list is long enough to fold, in both states, so expanding is
        // never a one-way door.
        guard allRows.count > Self.collapsedRowLimit else {
            return
        }
        stack.addFullWidthArrangedSubview(divider())
        stack.addFullWidthArrangedSubview(
            expansionToggleRow(
                remaining: allRows.count - Self.collapsedRowLimit,
                typography: configuration.typography
            )
        )
    }

    /// Appends the rest in place — or folds it back — rather than opening anything, so the card
    /// stays the whole answer.
    func expansionToggleRow(remaining: Int, typography: TranscriptTypography) -> NSView {
        let container = AppKitHostToolWidgetBubbleView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isInteractive = true
        container.setAccessibilityLabel(
            isExpanded ? "Show fewer pull requests" : "Show \(remaining) more pull requests"
        )
        let highlight = rowHighlight(in: container)
        container.onHoverChanged = { [weak highlight] isHovered in
            highlight?.setLayerFillColor(.secondaryLabelColor, alpha: isHovered ? 0.10 : 0)
        }
        container.onActivate = { [weak self] in
            guard let self, let configuration = self.configuration else {
                return
            }
            isExpanded.toggle()
            rebuild(configuration)
            // The card just changed size; the transcript measures rows from their content, so it
            // has to remeasure this one or the rows below sit at the old offsets.
            onHeightInvalidated?()
        }

        let title = label(
            isExpanded ? "Show less" : "Show \(remaining) more",
            font: typography.nsFont(.caption, weight: .semibold),
            color: .secondaryLabelColor
        )
        let content = NSStackView(views: [
            expansionChevron(typography: typography),
            title
        ])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = Self.iconSpacing
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.rowVerticalPadding),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.rowVerticalPadding)
        ])
        return container
    }

    /// Points the way the row moves the list. Decorative — the container's
    /// accessibility label already says which direction it goes.
    private func expansionChevron(typography: TranscriptTypography) -> NSView {
        let size = typography.size(for: .toolIcon)
        let view = AppKitDynamicTintImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setAccessibilityElement(false)
        view.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.up" : "chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: size, weight: .semibold))
        view.setDynamicContentTintColor(.secondaryLabelColor)
        return view
    }

    /// A hairline between rows, so the stack reads as a list rather than one run-on block. Tinted
    /// like the card's own fill rather than `separatorColor`, which is drawn for window chrome and
    /// reads as a hard rule against the bubble.
    func divider() -> NSView {
        let line = AppKitFlippedDynamicColorView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.setLayerFillColor(.secondaryLabelColor, alpha: 0.18)
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    func rowView(
        _ row: PullRequestListWidgetContent.Row,
        configuration: Configuration
    ) -> NSView {
        // The same interactive container the card shell uses, so a row gets hover, the
        // pointing-hand cursor, the press, and the button role for free. The hover fill draws on
        // an inset, rounded highlight view rather than the container itself, matching the sidebar
        // thread rows — a full-bleed square fill reads as a table, not a selectable row.
        let container = AppKitHostToolWidgetBubbleView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isInteractive = true
        container.onActivate = { [weak self] in
            self?.onOpenPullRequest?(row.identifier)
        }
        let highlight = rowHighlight(in: container)
        container.onHoverChanged = { [weak highlight] isHovered in
            highlight?.setLayerFillColor(.secondaryLabelColor, alpha: isHovered ? 0.10 : 0)
        }
        let title = AppMarkdownInlineLabel.plainText(from: row.title, detectingFileMentions: false)
        container.setAccessibilityLabel(
            "\(row.status.accessibilityName), \(row.identifier.displayKey), \(title)"
        )

        let icon = statusIcon(row.status, typography: configuration.typography)
        let lines = textLines(row, typography: configuration.typography)
        let slot = AppKitHostToolWidgetDisclosureSlotView()
        slot.setContentHuggingPriority(.required, for: .horizontal)
        slot.configure(
            size: configuration.typography.size(for: .caption),
            capHeight: configuration.typography.nsFont(.toolSummary).capHeight
        )

        let content = NSStackView(views: [icon, lines, slot])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = Self.iconSpacing
        // Gravity-area packing would leave every row's chevron wherever its text happened to
        // end; filling hands the slack to the lines so the chevrons line up down the card.
        content.distribution = .fill
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.rowVerticalPadding),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.rowVerticalPadding)
        ])
        return container
    }

    /// The rounded hover surface behind a row's content, outset past the text like the sidebar's
    /// selection chrome so the fill never sits flush against the glyphs.
    func rowHighlight(in container: AppKitHostToolWidgetBubbleView) -> AppKitFlippedDynamicColorView {
        let highlight = AppKitFlippedDynamicColorView()
        highlight.translatesAutoresizingMaskIntoConstraints = false
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = AppCornerRadius.standard
        highlight.setLayerFillColor(.secondaryLabelColor, alpha: 0)
        container.addSubview(highlight)
        NSLayoutConstraint.activate([
            highlight.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: -Self.highlightOutset),
            highlight.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: Self.highlightOutset),
            highlight.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            highlight.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -1)
        ])
        return highlight
    }

    /// Two stacked lines, matching the link card's own row. Status is the leading glyph, so it is
    /// deliberately absent here.
    func textLines(
        _ row: PullRequestListWidgetContent.Row,
        typography: TranscriptTypography
    ) -> NSStackView {
        let key = label(
            row.identifier.displayKey,
            font: typography.nsFont(.toolSummary),
            color: .labelColor
        )
        let detail = markdownLabel(
            row.title,
            font: typography.nsFont(.caption),
            color: .secondaryLabelColor
        )

        let lines = NSStackView(views: [key, detail])
        lines.translatesAutoresizingMaskIntoConstraints = false
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 1
        lines.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The lines are the row's only flexible child, so they take the slack and push the
        // chevron to the trailing edge instead of letting the row pack left.
        lines.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return lines
    }

    /// GitHub's own status octicon and tint, from the same mapping the Pull Requests screen uses,
    /// so a row reads its state the way the rest of the app does. The glyph is decorative: the
    /// status name still reaches VoiceOver through the row's accessibility label.
    func statusIcon(_ status: PullRequestStatus, typography: TranscriptTypography) -> NSView {
        let size = typography.size(for: .toolIcon)
        let view = AppKitDynamicTintImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setAccessibilityElement(false)
        if let asset = NSImage(named: PullRequestStatusGlyph.octicon(for: status).assetName) {
            let scaled = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                asset.draw(in: rect)
                return true
            }
            scaled.isTemplate = true
            view.image = scaled
        }
        view.setDynamicContentTintColor(PullRequestStatusGlyph.nsTint(for: status))
        return view
    }

    func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        return field
    }

    /// A pull request title is author-written and routinely carries backticked identifiers, so it
    /// renders as markdown rather than the raw string. The fill is the muted wash, not the regular
    /// chip gray, because this line is already `secondaryLabelColor`.
    func markdownLabel(_ markdown: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.attributedStringValue = AppKitMarkdownInlineString.attributedString(
            for: markdown,
            baseFont: font,
            foregroundColor: color,
            inlineCodeFill: AppKitMarkdownInlineString.mutedInlineCodeFill(over: color)
        )
        field.maximumNumberOfLines = 1
        return field
    }
}
