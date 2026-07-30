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
    let loadImage: (DiffImageVersion) async throws -> DiffImagePreviewOutput
    let openImage: (DiffImageVersion) async throws -> Void
    let commentAnnotations: DiffCommentAnnotations
    let commentInteraction: DiffCommentInteraction?
    /// Scrolls with the content (unlike host-side padding, which would clip
    /// rows at a fixed gap); the PR pane uses it to match its sibling tabs'
    /// top content inset. The diff viewer keeps the default 0.
    let contentTopInset: CGFloat
    @State private var preparedRows: FlattenedDiffPreviewPreparedRows?
    @State private var preparedRowsID: Int?

    init(
        files: [DiffFile],
        imagePreviews: [String: DiffImagePreview] = [:],
        showsFileHeaders: Bool,
        allowsFileCollapse: Bool = false,
        collapsedFileIDs: Set<String> = [],
        onToggleFileCollapse: @escaping (String) -> Void = { _ in },
        loadImage: @escaping (DiffImageVersion) async throws -> DiffImagePreviewOutput = { _ in throw DiffImagePreviewLoaderError.unsupportedImage },
        openImage: @escaping (DiffImageVersion) async throws -> Void = { _ in },
        commentAnnotations: DiffCommentAnnotations = .none,
        commentInteraction: DiffCommentInteraction? = nil,
        contentTopInset: CGFloat = 0
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

    private func clearPreparedRows() {
        preparedRows = nil
        preparedRowsID = nil
    }

    private func rowsView(_ preparedRows: FlattenedDiffPreviewPreparedRows) -> some View {
        DiffPreviewScrollContainer(minimumScrollableContentWidth: preparedRows.minimumScrollableContentWidth) {
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
                        commentInteraction: commentInteraction
                    )
                }
            }
            .padding(.top, contentTopInset)
            .appExpansionAnimationOverride(value: collapsedFileIDs)
            .diffPreviewMinimumContentWidthFrame()
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .textSelection(.enabled)
        }
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
    case commentThread(id: String, thread: DiffLineCommentThread, anchor: DiffCommentAnchor)
    case commentComposer(id: String, anchor: DiffCommentAnchor)

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
             .commentThread(let id, _, _),
             .commentComposer(let id, _):
            return id
        }
    }
}

private struct FlattenedDiffPreviewRenderRow: View {
    let row: FlattenedDiffPreviewRow
    let allowsFileCollapse: Bool
    let collapsedFileIDs: Set<String>
    let onToggleFileCollapse: (String) -> Void
    let loadImage: (DiffImageVersion) async throws -> DiffImagePreviewOutput
    let openImage: (DiffImageVersion) async throws -> Void
    let allowsCommentComposing: Bool
    let commentInteraction: DiffCommentInteraction?

    @ViewBuilder
    var body: some View {
        switch row {
        case .fileHeader(_, let fileID, let file, let topPadding):
            let collapseState = collapseState(for: fileID)
            DiffPreviewFileHeader(
                file: file,
                collapseState: collapseState
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
        case .commentThread(_, let thread, let anchor):
            DiffCommentThreadRow(thread: thread, anchor: anchor, interaction: commentInteraction)
        case .commentComposer(_, let anchor):
            if let commentInteraction {
                DiffCommentComposerRow(anchor: anchor, interaction: commentInteraction)
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
