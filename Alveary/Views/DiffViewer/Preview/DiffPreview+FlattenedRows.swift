import AppKit
import SwiftUI

struct FlattenedDiffPreview: View {
    private static let synchronousLineThreshold = 1_000

    let files: [DiffFile]
    let imagePreviews: [String: DiffImagePreview]
    let showsFileHeaders: Bool
    let allowsFileCollapse: Bool
    let collapsedFileIDs: Set<String>
    let onToggleFileCollapse: (String) -> Void
    let loadImage: (DiffImageVersion, DiffImageLoadIntent) async throws -> DiffImagePreviewOutput
    let openImage: (DiffImageVersion) async throws -> Void
    let commentAnnotations: DiffCommentAnnotations
    let commentInteraction: DiffCommentInteraction?
    /// Scrolls with the content (unlike host-side padding, which would clip
    /// rows at a fixed gap); the PR pane uses it to match its sibling tabs'
    /// top content inset. The diff viewer keeps the default 0.
    let contentTopInset: CGFloat
    /// Horizontal padding inside the scroll container. The PR pane folds its
    /// pane inset into this so the scroll bar sits flush with the pane edge
    /// (host-side padding would inset the scroller with it); the diff viewer
    /// keeps the default.
    let horizontalContentInset: CGFloat
    /// Axis the file headers' collapse carets center their *ink* on, measured from
    /// the scroll view's trailing edge. `nil` leaves each caret its natural inset
    /// inboard of the diff's own content edge, which is the diff viewer's behavior;
    /// the PR pane passes `ContextualPaneLayout.trailingGlyphAxis` so the carets join
    /// the lane the header's close button and Open-on-GitHub button sit on.
    let collapseCaretAxis: CGFloat?
    /// A one-shot ask to bring one row into view. Deliberately absent from
    /// `renderFingerprint` — it changes no row, and folding it in would rebuild
    /// every prepared row (and flash the preparing state on a large diff) for a
    /// scroll. The owner keeps the pending state; this only reports back.
    let scrollTarget: FlattenedDiffPreviewScrollTarget?
    /// Called once the scroll for `token` has been attempted, whether or not the
    /// row existed, so the owner can clear its one-shot state instead of
    /// retrying forever against a row the diff no longer contains.
    let onScrollTargetConsumed: ((UUID) -> Void)?
    @State private var preparedRows: FlattenedDiffPreviewPreparedRows?
    @State private var preparedRowsID: Int?

    init(
        files: [DiffFile],
        imagePreviews: [String: DiffImagePreview] = [:],
        showsFileHeaders: Bool,
        allowsFileCollapse: Bool = false,
        collapsedFileIDs: Set<String> = [],
        onToggleFileCollapse: @escaping (String) -> Void = { _ in },
        loadImage: @escaping (DiffImageVersion, DiffImageLoadIntent) async throws -> DiffImagePreviewOutput = { _, _ in
            throw DiffImagePreviewLoaderError.unsupportedImage
        },
        openImage: @escaping (DiffImageVersion) async throws -> Void = { _ in },
        commentAnnotations: DiffCommentAnnotations = .none,
        commentInteraction: DiffCommentInteraction? = nil,
        contentTopInset: CGFloat = 0,
        horizontalContentInset: CGFloat = DiffViewerPaneMetrics.diffPreviewHorizontalInset,
        collapseCaretAxis: CGFloat? = nil,
        scrollTarget: FlattenedDiffPreviewScrollTarget? = nil,
        onScrollTargetConsumed: ((UUID) -> Void)? = nil
    ) {
        self.files = files
        self.imagePreviews = imagePreviews
        self.showsFileHeaders = showsFileHeaders
        self.allowsFileCollapse = allowsFileCollapse
        self.collapsedFileIDs = collapsedFileIDs
        self.onToggleFileCollapse = onToggleFileCollapse
        self.loadImage = loadImage
        self.openImage = openImage
        self.commentAnnotations = commentAnnotations
        self.commentInteraction = commentInteraction
        self.contentTopInset = contentTopInset
        self.horizontalContentInset = horizontalContentInset
        self.collapseCaretAxis = collapseCaretAxis
        self.scrollTarget = scrollTarget
        self.onScrollTargetConsumed = onScrollTargetConsumed
    }

    var body: some View {
        let currentRenderID = renderFingerprint
        if estimatedLineCount <= Self.synchronousLineThreshold {
            rowsView(
                FlattenedDiffPreviewRows.makeRows(
                    files: files,
                    imagePreviews: imagePreviews,
                    showsFileHeaders: showsFileHeaders,
                    allowsFileCollapse: allowsFileCollapse,
                    collapsedFileIDs: collapsedFileIDs,
                    commentAnnotations: commentAnnotations
                )
            )
                .task(id: currentRenderID) {
                    clearPreparedRows()
                }
        } else if let preparedRows,
                  preparedRowsID == currentRenderID {
            rowsView(preparedRows)
        } else {
            preparingView
                .task(id: currentRenderID) {
                    let files = files
                    let showsFileHeaders = showsFileHeaders
                    let imagePreviews = imagePreviews
                    let allowsFileCollapse = allowsFileCollapse
                    let collapsedFileIDs = collapsedFileIDs
                    let commentAnnotations = commentAnnotations
                    let currentRenderID = currentRenderID
                    preparedRows = nil
                    preparedRowsID = nil
                    let rowTask = Task.detached(priority: .userInitiated) {
                        try FlattenedDiffPreviewRows.makeRowsUnlessCancelled(
                            files: files,
                            imagePreviews: imagePreviews,
                            showsFileHeaders: showsFileHeaders,
                            allowsFileCollapse: allowsFileCollapse,
                            collapsedFileIDs: collapsedFileIDs,
                            commentAnnotations: commentAnnotations
                        )
                    }
                    do {
                        // Propagate SwiftUI task cancellation into the detached row builder.
                        let rows = try await withTaskCancellationHandler {
                            try await rowTask.value
                        } onCancel: {
                            rowTask.cancel()
                        }
                        guard !Task.isCancelled else {
                            return
                        }
                        preparedRows = rows
                        preparedRowsID = currentRenderID
                    } catch is CancellationError {
                        rowTask.cancel()
                        return
                    } catch {
                        rowTask.cancel()
                    }
                }
        }
    }

    /// How far past the content inset a file header must reach for its caret to
    /// center on `collapseCaretAxis`. The caret's ink centers in its own square
    /// frame — the rotation that opens it turns about that same center — so the
    /// frame's midpoint is the whole calculation. Derived rather than passed so a
    /// change to `horizontalContentInset` cannot leave the caret behind; clamped at
    /// zero because an axis *inside* the diff's own edge is the natural placement.
    private var fileHeaderTrailingExtension: CGFloat {
        guard let collapseCaretAxis else {
            return 0
        }
        let naturalAxis = horizontalContentInset + DiffPreviewFileHeader.collapseCaretFrameWidth / 2
        return max(naturalAxis - collapseCaretAxis, 0)
    }

    private func clearPreparedRows() {
        preparedRows = nil
        preparedRowsID = nil
    }

    private func rowsView(_ preparedRows: FlattenedDiffPreviewPreparedRows) -> some View {
        ScrollViewReader { proxy in
            scrollTargetObserver(
                DiffPreviewScrollContainer(
                    minimumScrollableContentWidth: preparedRows.minimumScrollableContentWidth,
                    horizontalContentPadding: horizontalContentInset
                ) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(preparedRows.rows) { row in
                            FlattenedDiffPreviewRenderRow(
                                row: row,
                                allowsFileCollapse: allowsFileCollapse,
                                collapsedFileIDs: collapsedFileIDs,
                                onToggleFileCollapse: onToggleFileCollapse,
                                loadImage: loadImage,
                                openImage: openImage,
                                allowsCommentComposing: commentAnnotations.allowsComposing,
                                commentInteraction: commentInteraction,
                                fileHeaderTrailingExtension: fileHeaderTrailingExtension
                            )
                        }
                    }
                    .padding(.top, contentTopInset)
                    .appExpansionAnimationOverride(value: collapsedFileIDs)
                    .diffPreviewMinimumContentWidthFrame()
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                },
                proxy: proxy,
                rows: preparedRows.rows
            )
        }
    }

    /// Performs a pending scroll and reports it consumed. Both edges are needed: a target set
    /// while the diff was still loading arrives before this view exists (`task`), and one set
    /// against an already-rendered diff arrives after (`onChange`). Lifted out of `rowsView` to
    /// keep the modifiers off its type-check budget.
    private func scrollTargetObserver<Content: View>(
        _ content: Content,
        proxy: ScrollViewProxy,
        rows: [FlattenedDiffPreviewRow]
    ) -> some View {
        content
            .task(id: scrollTarget) {
                scrollToTarget(proxy: proxy, rows: rows)
            }
            .onChange(of: scrollTarget) { _, _ in
                scrollToTarget(proxy: proxy, rows: rows)
            }
    }

    /// Reports consumption even when the row is absent. A pull request pushed to since a review
    /// proposal was written can strand an anchor, and retrying forever would leave the owner's
    /// one-shot state armed against a row that is never coming.
    private func scrollToTarget(proxy: ScrollViewProxy, rows: [FlattenedDiffPreviewRow]) {
        guard let scrollTarget else {
            return
        }
        if rows.contains(where: { $0.id == scrollTarget.rowID }) {
            proxy.scrollTo(scrollTarget.rowID, anchor: .center)
        }
        onScrollTargetConsumed?(scrollTarget.token)
    }

    private var preparingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Preparing diff preview...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var estimatedLineCount: Int {
        files.enumerated().reduce(0) { total, entry in
            let (fileIndex, file) = entry
            if isFileCollapsed(file, fileIndex: fileIndex) {
                return total
            }

            return total + file.hunks.reduce(0) { $0 + $1.lines.count }
        }
    }

    private var renderFingerprint: Int {
        // Include line content so a large diff cannot reuse prepared rows from
        // another diff with the same file paths and hunk shape.
        var hasher = Hasher()
        hasher.combine(showsFileHeaders)
        hasher.combine(allowsFileCollapse)
        hasher.combine(commentAnnotations)
        if allowsFileCollapse {
            for collapsedFileID in collapsedFileIDs.sorted() {
                hasher.combine(collapsedFileID)
            }
        }
        for (fileIndex, file) in files.enumerated() {
            hasher.combine(file.oldPath)
            hasher.combine(file.newPath)
            hasher.combine(file.isBinary)
            hasher.combine(file.isRenamed)
            hasher.combine(imagePreviews[DiffImagePreviewSupport.fileID(for: file, fileIndex: fileIndex)])
            if isFileCollapsed(file, fileIndex: fileIndex) {
                // Collapsed headers still show counts, but hidden line content should not
                // force large prepared previews to rebuild.
                hasher.combine(file.linesAdded)
                hasher.combine(file.linesDeleted)
                continue
            }

            for hunk in file.hunks {
                hasher.combine(hunk.oldStart)
                hasher.combine(hunk.oldCount)
                hasher.combine(hunk.newStart)
                hasher.combine(hunk.newCount)
                hasher.combine(hunk.header)
                for line in hunk.lines {
                    hasher.combine(line.type.hashKey)
                    hasher.combine(line.oldLineNumber)
                    hasher.combine(line.newLineNumber)
                    hasher.combine(line.content)
                }
            }
        }
        return hasher.finalize()
    }

    private func isFileCollapsed(_ file: DiffFile, fileIndex: Int) -> Bool {
        showsFileHeaders
            && allowsFileCollapse
            && collapsedFileIDs.contains(FlattenedDiffPreviewRows.fileCollapseID(for: file, fileIndex: fileIndex))
    }
}

private extension DiffLine.LineType {
    var hashKey: Int {
        switch self {
        case .context:
            return 0
        case .added:
            return 1
        case .deleted:
            return 2
        }
    }
}

/// A one-shot ask to bring one prepared row into view. The token is what consumption matches on,
/// so a late consumer cannot swallow a newer request.
struct FlattenedDiffPreviewScrollTarget: Equatable {
    let token: UUID
    let rowID: String
}

struct FlattenedDiffPreviewPreparedRows: Sendable {
    let rows: [FlattenedDiffPreviewRow]
    let minimumScrollableContentWidth: CGFloat
}
enum FlattenedDiffPreviewRow: Identifiable, Sendable {
    case fileHeader(id: String, fileID: String, file: DiffFile, topPadding: CGFloat)
    case renameSummary(id: String, oldPath: String, newPath: String)
    case imagePreview(id: String, preview: DiffImagePreview)
    case binaryCallout(id: String)
    case emptyCallout(id: String, isRenamed: Bool)
    case hunkHeader(id: String, hunk: DiffHunk, topPadding: CGFloat)
    case line(
        id: String,
        line: DiffLine,
        gutterLayout: DiffGutterLayout,
        isLastInHunk: Bool,
        bottomPadding: CGFloat,
        commentAnchor: DiffCommentAnchor?
    )
    case collapsed(id: String, summary: CollapsedContextSummary, gutterLayout: DiffGutterLayout, isLastInHunk: Bool, bottomPadding: CGFloat)
    case fileContentSpacer(id: String, height: CGFloat)
    // Comment rows carry the hunk-row chrome flags so the code surface flows
    // continuously behind their floating cards; when one is the hunk's final
    // row, it owns the bottom rounding its anchored line row gives up. They
    // also carry a wash so the neighboring lines' tints surround the card
    // instead of stopping above it.
    case commentThread(
        id: String,
        thread: DiffLineCommentThread,
        anchor: DiffCommentAnchor,
        wash: DiffCommentRowWash,
        isLastInHunk: Bool,
        bottomPadding: CGFloat
    )
    case commentComposer(
        id: String,
        anchor: DiffCommentAnchor,
        wash: DiffCommentRowWash,
        isLastInHunk: Bool,
        bottomPadding: CGFloat
    )

    var id: String {
        switch self {
        case .fileHeader(let id, _, _, _),
             .renameSummary(let id, _, _),
             .imagePreview(let id, _),
             .binaryCallout(let id),
             .emptyCallout(let id, _),
             .hunkHeader(let id, _, _),
             .line(let id, _, _, _, _, _),
             .collapsed(let id, _, _, _, _),
             .fileContentSpacer(let id, _),
             .commentThread(let id, _, _, _, _, _),
             .commentComposer(let id, _, _, _, _):
            return id
        }
    }
}

private struct FlattenedDiffPreviewRenderRow: View {
    let row: FlattenedDiffPreviewRow
    let allowsFileCollapse: Bool
    let collapsedFileIDs: Set<String>
    let onToggleFileCollapse: (String) -> Void
    let loadImage: (DiffImageVersion, DiffImageLoadIntent) async throws -> DiffImagePreviewOutput
    let openImage: (DiffImageVersion) async throws -> Void
    let allowsCommentComposing: Bool
    let commentInteraction: DiffCommentInteraction?
    let fileHeaderTrailingExtension: CGFloat

    @ViewBuilder
    var body: some View {
        switch row {
        case .fileHeader(_, let fileID, let file, let topPadding):
            let collapseState = collapseState(for: fileID)
            DiffPreviewFileHeader(
                file: file,
                collapseState: collapseState,
                trailingExtension: fileHeaderTrailingExtension
            )
                .padding(.top, topPadding)
                .padding(.bottom, collapseState?.isCollapsed == true ? 4 : 10)
                .zIndex(1)
        case .renameSummary(_, let oldPath, let newPath):
            DiffPreviewRenameSummary(oldPath: oldPath, newPath: newPath)
                .padding(.bottom, 14)
        case .imagePreview(_, let preview):
            DiffImagePreviewSlots(
                preview: preview,
                loadImage: loadImage,
                openImage: openImage
            )
            .frame(minHeight: 280)
            .padding(.bottom, 14)
        case .binaryCallout:
            DiffCalloutCard(
                icon: "doc.fill",
                title: "Binary diff",
                message: "Binary file changes cannot be rendered inline yet."
            )
        case .emptyCallout(_, let isRenamed):
            DiffCalloutCard(
                icon: "arrow.left.arrow.right",
                title: isRenamed ? "Rename only" : "No line changes",
                message: isRenamed
                    ? "This change renames the file without modifying any lines."
                    : "This change does not contain any line-based hunks to render."
            )
        case .hunkHeader(_, let hunk, let topPadding):
            DiffPreviewHunkHeader(hunk: hunk)
                .padding(.top, topPadding)
        case .line(_, let line, let gutterLayout, let isLastInHunk, let bottomPadding, let commentAnchor):
            let lineRow = DiffLineRow(line: line, gutterLayout: gutterLayout)
                .diffPreviewFlattenedHunkRow(isLastInHunk: isLastInHunk, bottomPadding: bottomPadding)
            if let commentAnchor, allowsCommentComposing, let commentInteraction {
                DiffCommentableLineRow(
                    anchor: commentAnchor,
                    gutterLayout: gutterLayout,
                    onAddComment: commentInteraction.onAddComment
                ) {
                    lineRow
                }
            } else {
                lineRow
            }
        case .collapsed(_, let summary, let gutterLayout, let isLastInHunk, let bottomPadding):
            DiffCollapsedContextRow(summary: summary, gutterLayout: gutterLayout)
                .diffPreviewFlattenedHunkRow(isLastInHunk: isLastInHunk, bottomPadding: bottomPadding)
        case .fileContentSpacer(_, let height):
            Color.clear
                .frame(height: height)
        case .commentThread(_, let thread, let anchor, let wash, let isLastInHunk, let bottomPadding):
            DiffCommentThreadRow(thread: thread, anchor: anchor, interaction: commentInteraction)
                .diffPreviewFlattenedHunkRow(
                    isLastInHunk: isLastInHunk,
                    bottomPadding: bottomPadding,
                    commentWash: wash
                )
        case .commentComposer(_, let anchor, let wash, let isLastInHunk, let bottomPadding):
            if let commentInteraction {
                DiffCommentComposerRow(anchor: anchor, interaction: commentInteraction)
                    .diffPreviewFlattenedHunkRow(
                        isLastInHunk: isLastInHunk,
                        bottomPadding: bottomPadding,
                        commentWash: wash
                    )
            }
        }
    }

    private func collapseState(for fileID: String) -> DiffPreviewFileHeaderCollapseState? {
        guard allowsFileCollapse else {
            return nil
        }

        return DiffPreviewFileHeaderCollapseState(
            isCollapsed: collapsedFileIDs.contains(fileID),
            onToggle: {
                withAnimation(appExpansionAnimation) {
                    onToggleFileCollapse(fileID)
                }
            }
        )
    }
}
