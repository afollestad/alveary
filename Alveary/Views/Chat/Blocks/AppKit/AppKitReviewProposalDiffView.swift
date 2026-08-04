import AppKit

/// The pending review comments on the diff lines they were written against, rendered natively.
///
/// This deliberately does not host `FlattenedDiffPreview`: that view wraps its rows in a
/// `ScrollView`, which reports no intrinsic height, so a transcript row measuring itself from its
/// content gets a collapsed card with its controls laid over the clipped diff. A transcript card
/// cannot scroll anyway — the preview is already narrowed to the commented hunks, and the whole
/// diff stays one Review… away — so plain stacked rows are both simpler and stable.
@MainActor
final class AppKitReviewProposalDiffView: NSView {
    private let stack = NSStackView()
    private var renderedPreview: PullRequestReviewProposalPreview?
    private var renderedTypography: TranscriptTypography?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
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

    func configure(preview: PullRequestReviewProposalPreview, typography: TranscriptTypography) {
        guard renderedPreview != preview || renderedTypography != typography else {
            return
        }
        renderedPreview = preview
        renderedTypography = typography
        rebuild(preview: preview, typography: typography)
    }

    /// The widest rendered row, so the card can size to its content like every other widget body.
    var naturalWidth: CGFloat {
        stack.arrangedSubviews.reduce(CGFloat.zero) { widest, row in
            max(widest, ceil(row.fittingSize.width))
        }
    }
}

private extension AppKitReviewProposalDiffView {
    func rebuild(preview: PullRequestReviewProposalPreview, typography: TranscriptTypography) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for file in preview.files {
            stack.addFullWidthArrangedSubview(fileHeader(file.path, typography: typography))
            for hunk in file.hunks {
                appendHunk(hunk, file: file, preview: preview, typography: typography)
            }
        }
    }

    /// Lines within `contextRadius` of a commented line render; the rest collapse into ellipsis
    /// rows. A hunk can span hundreds of lines and the card cannot scroll, so the anchor context
    /// is the part worth the height — the whole diff stays one Review… away.
    static let contextRadius = 3

    func appendHunk(
        _ hunk: DiffHunk,
        file: DiffFile,
        preview: PullRequestReviewProposalPreview,
        typography: TranscriptTypography
    ) {
        let anchoredIndexes = hunk.lines.indices.filter { index in
            !threads(at: hunk.lines[index], path: file.path, preview: preview).isEmpty
        }
        var didElide = false
        for (index, line) in hunk.lines.enumerated() {
            let isNearAnchor = anchoredIndexes.contains { abs($0 - index) <= Self.contextRadius }
            guard isNearAnchor else {
                if !didElide {
                    stack.addFullWidthArrangedSubview(elisionRow(typography: typography))
                    didElide = true
                }
                continue
            }
            didElide = false
            stack.addFullWidthArrangedSubview(lineRow(line, typography: typography))
            for thread in threads(at: line, path: file.path, preview: preview) {
                for comment in thread.comments {
                    stack.addFullWidthArrangedSubview(commentRow(comment, typography: typography))
                }
            }
        }
    }

    func elisionRow(typography: TranscriptTypography) -> NSView {
        let label = NSTextField(labelWithString: "⋯")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedSystemFont(ofSize: typography.size(for: .caption), weight: .regular)
        label.textColor = .tertiaryLabelColor
        let container = AppKitFlippedDynamicColorView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    /// A comment anchors on whichever side's number it was written against, matching the GitHub
    /// review API: added and context lines on the right, deleted lines on the left.
    func threads(
        at line: DiffLine,
        path: String,
        preview: PullRequestReviewProposalPreview
    ) -> [DiffLineCommentThread] {
        var anchors: [DiffCommentAnchor] = []
        if let newLine = line.newLineNumber {
            anchors.append(DiffCommentAnchor(path: path, side: .right, line: newLine))
        }
        if let oldLine = line.oldLineNumber {
            anchors.append(DiffCommentAnchor(path: path, side: .left, line: oldLine))
        }
        return anchors.compactMap { preview.annotations.threads[$0] }
    }

    func fileHeader(_ path: String, typography: TranscriptTypography) -> NSView {
        let label = NSTextField(labelWithString: path)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: typography.size(for: .caption), weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingHead
        label.maximumNumberOfLines = 1
        let container = AppKitFlippedDynamicColorView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])
        return container
    }

    func lineRow(_ line: DiffLine, typography: TranscriptTypography) -> NSView {
        let row = AppKitFlippedDynamicColorView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        if let tint = Self.tint(for: line.type) {
            row.setLayerFillColor(tint.color, alpha: tint.alpha)
        }
        let label = NSTextField(labelWithString: "\(Self.marker(for: line.type))\(line.content)")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedSystemFont(ofSize: typography.size(for: .caption), weight: .regular)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -1)
        ])
        return row
    }

    /// The comment as it will be published, attributed and indented under its line.
    func commentRow(_ comment: DiffLineComment, typography: TranscriptTypography) -> NSView {
        let container = AppKitFlippedDynamicColorView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let author = NSTextField(labelWithString: comment.author)
        author.translatesAutoresizingMaskIntoConstraints = false
        author.font = NSFont.systemFont(ofSize: typography.size(for: .caption), weight: .semibold)
        author.textColor = .secondaryLabelColor
        let body = NSTextField(wrappingLabelWithString: comment.bodyMarkdown)
        body.translatesAutoresizingMaskIntoConstraints = false
        body.font = NSFont.systemFont(ofSize: typography.size(for: .caption))
        body.textColor = .labelColor
        body.isSelectable = false
        container.addSubview(author)
        container.addSubview(body)
        NSLayoutConstraint.activate([
            author.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            author.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            author.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            body.leadingAnchor.constraint(equalTo: author.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            body.topAnchor.constraint(equalTo: author.bottomAnchor, constant: 2),
            body.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    static func marker(for type: DiffLine.LineType) -> String {
        switch type {
        case .added:
            "+"
        case .deleted:
            "-"
        case .context:
            " "
        }
    }

    static func tint(for type: DiffLine.LineType) -> (color: NSColor, alpha: CGFloat)? {
        switch type {
        case .added:
            (.systemGreen, 0.14)
        case .deleted:
            (.systemRed, 0.14)
        case .context:
            nil
        }
    }
}
