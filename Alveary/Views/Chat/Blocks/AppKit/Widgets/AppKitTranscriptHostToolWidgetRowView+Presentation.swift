@preconcurrency import AppKit

/// The widget shell's pure presentation helpers — functions of the entry alone, split out to
/// keep the row view inside the shared file-length limit.
extension AppKitTranscriptHostToolWidgetRowView {
    /// The summary's own subject carries the weight, so the pull request a review proposal asks
    /// about reads out of the sentence around it. The colour is set as an attribute because
    /// `attributedStringValue` supersedes `textColor`; `labelColor` stays dynamic through it.
    static func summaryString(_ summary: String, emphasizing name: String?, font: NSFont) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: summary,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        guard let name, let emphasized = summary.range(of: name) else {
            return attributed
        }
        attributed.addAttribute(
            .font,
            value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask),
            range: NSRange(emphasized, in: summary)
        )
        return attributed
    }

    /// The octicon a card wears in place of the shell's status glyph, naming the activity rather
    /// than an outcome. `nil` falls back to `statusSymbol(for:)`, which is what carries a failure —
    /// and a review proposal's verdict, once the user has given one.
    static func activityOcticon(for entry: HostToolWidgetEntry) -> Octicon? {
        guard !entry.isError else {
            return nil
        }
        switch entry.content {
        case .pullRequestReviewInstructions(let content):
            return content.status == .failed ? nil : .codeReview16
        case .pullRequestList(let content):
            return content.status == .failed ? nil : PullRequestStatusGlyph.octicon16(for: .open)
        case .pullRequestReviewProposal:
            return awaitsReviewDecision(entry) ? PullRequestStatusGlyph.octicon16(for: .open) : nil
        case .collectiveReviewRun(let run):
            return run.phase == .failed ? nil : .codeReview16
        case .scheduledTaskProposal, .pullRequestLink, .threadAction:
            return nil
        }
    }

    static func awaitsReviewDecision(_ entry: HostToolWidgetEntry) -> Bool {
        guard case .pullRequestReviewProposal = entry.content else {
            return false
        }
        return !entry.isError && entry.outcome == nil && !entry.isSettledWithoutDecision
    }

    /// Fixed-canvas octicon artwork does not size by font, so it is redrawn at the icon size the
    /// way the pull-request list card's rows do it.
    func octicon(_ octicon: Octicon, size: CGFloat) -> NSImage? {
        guard let asset = NSImage(named: octicon.assetName) else {
            return nil
        }
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            asset.draw(in: rect)
            return true
        }
    }

    func statusSymbol(for entry: HostToolWidgetEntry) -> (name: String, tint: NSColor) {
        if entry.isError {
            return ("exclamationmark.triangle", .systemRed)
        }
        if case .collectiveReviewRun(let run) = entry.content, run.phase == .cancelled || run.phase == .interrupted {
            return ("xmark.circle", .secondaryLabelColor)
        }
        switch entry.outcome {
        case .confirmed:
            return ("checkmark.circle", .systemGreen)
        case .rejected:
            return ("xmark.circle", .secondaryLabelColor)
        case nil:
            return entry.isSettledWithoutDecision
                ? ("checkmark.circle", .systemGreen)
                : ("clock", .secondaryLabelColor)
        }
    }
}

/// Installs the prepared review body without parsing during measurement.
extension AppKitTranscriptHostToolWidgetRowView {
    /// Its own function so `updateBody` stays inside the shared function-length limit; the
    /// proposal is the one body here with live confirmation state to thread through.
    func updateReviewProposalBody(
        _ content: PullRequestReviewProposalWidgetContent,
        configuration: Configuration
    ) {
        let state = configuration.reviewProposal ?? ReviewProposalWidgetState()
        reviewProposalBody.avatarLoader = avatarLoader
        reviewProposalBody.configure(
            .init(
                content: content,
                presentation: state.presentation,
                preview: state.preview,
                selectedEvent: state.selectedEvent,
                canSubmit: state.canSubmit,
                isInteractive: configuration.isProposalInteractive,
                isSubmitting: state.isSubmitting,
                outcome: configuration.entry.outcome,
                errorMessage: state.errorMessage ?? configuration.errorMessage,
                typography: configuration.typography,
                summaryBody: ReviewProposalWidgetState.summaryBody(for: configuration.entry, state: state) ?? "",
                summaryDocument: reviewSummaryDocument(configuration)
            )
        )
        reviewProposalBody.isHidden = !reviewProposalBody.hasContent
    }

}

extension AppKitTranscriptHostToolWidgetRowView {
    func reviewSummaryDocument(_ configuration: Configuration) -> AppMarkdownDocument? {
        if let document = configuration.reviewSummaryDocument { return document }
        guard let markdown = ReviewProposalWidgetState.summaryBody(for: configuration.entry, state: configuration.reviewProposal),
              !markdown.isEmpty else { return nil }
        return AppMarkdownDocumentCache.document(
            markdown: markdown,
            context: AppMarkdownDocumentCacheContext(baseURL: nil, inlineCodeStyle: .standard, composerChipMode: .none, taskStateScope: nil)
        ) {
            AppMarkdownParser().documentPreservingSource(for: markdown)
        }
    }
}
