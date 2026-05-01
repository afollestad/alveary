@preconcurrency import AppKit

extension NSView {
    var transcriptMarkdownTextViews: [AppKitMarkdownTextView] {
        subviews.flatMap { child -> [AppKitMarkdownTextView] in
            var matches = child.transcriptMarkdownTextViews
            if let textView = child as? AppKitMarkdownTextView {
                matches.insert(textView, at: 0)
            }
            return matches
        }
    }

    var transcriptNonTextMarkdownViews: [NSView] {
        subviews.flatMap { child -> [NSView] in
            var matches = child.transcriptNonTextMarkdownViews
            if child is AppKitMarkdownCodeBlockView || child is AppKitMarkdownTableView {
                matches.insert(child, at: 0)
            }
            return matches
        }
    }
}

extension AppKitMarkdownTextView {
    func transcriptNaturalTextWidth(constrainedTo maxWidth: CGFloat) -> CGFloat {
        guard let attributedString = textStorage else {
            return 0
        }

        let maxLineWidth = max(maxWidth, 1)
        let rect = attributedString.boundingRect(
            with: NSSize(width: maxLineWidth, height: CGFloat.greatestFiniteMagnitude / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.width + (textContainerInset.width * 2))
    }
}
