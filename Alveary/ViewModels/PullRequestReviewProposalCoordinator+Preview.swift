import Foundation

/// The diff-with-comments preview a review-proposal card renders.
enum PullRequestReviewProposalPreviewState: Equatable {
    case loading
    case loaded(PullRequestReviewProposalPreview)
    case failed(String)
}

/// Only the hunks the user's pending comments sit on, with those comments attached.
///
/// The card is a confirmation, not a review surface: it shows what confirming would publish, and
/// the pull request pane remains where the whole diff is read.
struct PullRequestReviewProposalPreview: Equatable {
    /// A transcript card cannot scroll, so a review spanning many files shows its first few and
    /// sends the rest to the pull request pane.
    static let maximumFiles = 5

    /// Hunk-filtered copies of the files carrying pending comments.
    let files: [DiffFile]
    let annotations: DiffCommentAnnotations
    let pendingCommentCount: Int
    /// Files with pending comments the card did not render.
    let hiddenFileCount: Int
    /// GitHub refuses approve and request-changes on the viewer's own pull request, so the card's
    /// verdict picker disables them.
    let viewerIsAuthor: Bool

    var isEmpty: Bool {
        files.isEmpty
    }
}

extension PullRequestReviewProposalCoordinator {
    /// Context lines kept around a commented hunk are the hunk's own — whole hunks only, so line
    /// numbers stay meaningful.
    func loadPreview(
        for presentation: PullRequestReviewProposalPresentation
    ) async -> PullRequestReviewProposalPreviewState {
        do {
            let detail = try await service.fetchDetail(presentation.identifier)
            let pendingThreads = detail.reviewThreads.filter { $0.isPending && $0.line != nil }
            let viewerIsAuthor = detail.viewerLogin.map { $0 == detail.authorLogin } ?? false
            guard !pendingThreads.isEmpty else {
                // A summary-only review has no comments to show; the card renders its body alone.
                return .loaded(
                    PullRequestReviewProposalPreview(
                        files: [],
                        annotations: DiffCommentAnnotations(),
                        pendingCommentCount: 0,
                        hiddenFileCount: 0,
                        viewerIsAuthor: viewerIsAuthor
                    )
                )
            }
            let diffText = try await service.fetchDiff(presentation.identifier)
            let files = Self.commentedFiles(in: DiffParser.parse(diffText), threads: pendingThreads)
            let shown = Array(files.prefix(PullRequestReviewProposalPreview.maximumFiles))
            return .loaded(
                PullRequestReviewProposalPreview(
                    files: shown,
                    annotations: Self.annotations(for: pendingThreads),
                    pendingCommentCount: pendingThreads.reduce(0) { $0 + $1.comments.count },
                    hiddenFileCount: files.count - shown.count,
                    viewerIsAuthor: viewerIsAuthor
                )
            )
        } catch {
            return .failed(Self.previewMessage(for: error))
        }
    }
}

private extension PullRequestReviewProposalCoordinator {
    /// Narrows to the files a pending comment sits on, and inside each to the hunks holding one.
    static func commentedFiles(
        in files: [DiffFile],
        threads: [PullRequestReviewThread]
    ) -> [DiffFile] {
        var anchorsByPath: [String: Set<Int>] = [:]
        for thread in threads {
            guard let line = thread.line else {
                continue
            }
            anchorsByPath[thread.path, default: []].insert(line)
        }
        return files.compactMap { file in
            guard let anchors = anchorsByPath[file.path] else {
                return nil
            }
            let hunks = file.hunks.filter { hunk in
                hunk.lines.contains { line in
                    // A comment anchors on whichever side's number it was written against, so
                    // either side matching keeps the hunk.
                    line.newLineNumber.map(anchors.contains) == true
                        || line.oldLineNumber.map(anchors.contains) == true
                }
            }
            guard !hunks.isEmpty else {
                return nil
            }
            return DiffFile(
                oldPath: file.oldPath,
                newPath: file.newPath,
                isBinary: file.isBinary,
                isRenamed: file.isRenamed,
                hunks: hunks
            )
        }
    }

    /// Inert annotations: the card renders threads read-only, with no composer and no interaction,
    /// so nothing on it can post to GitHub before the user confirms.
    static func annotations(for threads: [PullRequestReviewThread]) -> DiffCommentAnnotations {
        var annotations = DiffCommentAnnotations()
        annotations.allowsComposing = false
        for thread in threads {
            guard let line = thread.line else {
                continue
            }
            let anchor = DiffCommentAnchor(
                path: thread.path,
                side: thread.side == .left ? .left : .right,
                line: line
            )
            annotations.threads[anchor] = DiffLineCommentThread(
                comments: thread.comments.map { comment in
                    DiffLineComment(
                        author: comment.authorLogin,
                        bodyMarkdown: PullRequestMarkdown.sanitized(comment.bodyMarkdown),
                        isPending: comment.isPending,
                        remoteID: comment.databaseId,
                        nodeID: comment.nodeID,
                        avatarURL: comment.authorAvatarURL,
                        isBot: comment.isBot
                    )
                },
                isResolved: thread.isResolved,
                isOutdated: thread.isOutdated,
                threadID: thread.nodeID,
                isPending: thread.isPending
            )
        }
        return annotations
    }

    static func previewMessage(for error: Error) -> String {
        guard let serviceError = error as? PullRequestsServiceError else {
            return error.localizedDescription
        }
        return serviceError.errorDescription ?? serviceError.localizedDescription
    }
}
