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

    func readsReviewInstructions(_ entry: HostToolWidgetEntry) -> Bool {
        guard case .pullRequestReviewInstructions(let content) = entry.content else {
            return false
        }
        return !entry.isError && content.status != .failed
    }

    func awaitsReviewDecision(_ entry: HostToolWidgetEntry) -> Bool {
        guard case .pullRequestReviewProposal = entry.content else {
            return false
        }
        return !entry.isError && entry.outcome == nil && !entry.isSettledWithoutDecision
    }

    func pullRequestOcticon(size: CGFloat) -> NSImage? {
        octicon(named: PullRequestStatusGlyph.assetName16(for: .open), size: size)
    }

    /// Fixed-canvas octicon artwork does not size by font, so it is redrawn at the icon size the
    /// way the pull-request list card's rows do it.
    func octicon(named assetName: String, size: CGFloat) -> NSImage? {
        guard let asset = NSImage(named: assetName) else {
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
