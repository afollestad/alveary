import SwiftUI

/// Draws one row of the flattened stream. Split from `FlattenedDiffPreview` so the row switch and
/// the preview's own state each keep their own file.
struct FlattenedDiffPreviewRenderRow: View {
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
            // A *definite* box in both axes, not a minimum. The row contributes no scrollable
            // width and its scroll container proposes nil in each axis, so a `.fit` image answers
            // with its intrinsic size: a 1170x2532 phone screenshot measured a 3315pt row. The
            // width frame matters just as much — an unclamped row instead stretches to whatever
            // scroll width some *other* row's long line opened, which drove the same screenshot to
            // 17849pt. Current changes mode is already bounded this way by
            // `DiffImagePreviewScrollView`'s `GeometryReader`; full size is one click away.
            DiffImagePreviewSlots(
                preview: preview,
                loadImage: loadImage,
                openImage: openImage
            )
            .frame(height: DiffViewerPaneMetrics.diffPreviewImageRowHeight)
            .diffPreviewViewportContentWidthFrame()
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
