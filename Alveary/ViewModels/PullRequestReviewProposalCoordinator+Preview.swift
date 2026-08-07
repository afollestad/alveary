import Foundation

/// The diff-with-comments preview a review-proposal card renders.
enum PullRequestReviewProposalPreviewState: Equatable {
    case loading
    case loaded(PullRequestReviewProposalPreview)
    case failed(String)
}

/// Only the hunks the review's comments sit on, with those comments attached.
///
/// The card is a confirmation, not a review surface: it shows what confirming would publish, and
/// the pull request pane remains where the whole diff is read.
struct PullRequestReviewProposalPreview: Equatable {
    /// A transcript card cannot scroll, so a review spanning many files shows its first few and
    /// sends the rest to the pull request pane.
    static let maximumFiles = 5

    /// Hunk-filtered copies of the files carrying comments — the proposal's staged ones and any
    /// pending draft the user already holds on GitHub.
    let files: [DiffFile]
    let annotations: DiffCommentAnnotations
    /// The user's own already-pending draft comments on GitHub.
    let pendingCommentCount: Int
    /// The proposal's staged comments, existing only in Alveary until confirmed.
    let proposedCommentCount: Int
    /// Files with comments the card did not render.
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
            guard !pendingThreads.isEmpty || !presentation.comments.isEmpty else {
                // A summary-only review has no comments to show; the card renders its body alone.
                return .loaded(
                    PullRequestReviewProposalPreview(
                        files: [],
                        annotations: DiffCommentAnnotations(),
                        pendingCommentCount: 0,
                        proposedCommentCount: 0,
                        hiddenFileCount: 0,
                        viewerIsAuthor: viewerIsAuthor
                    )
                )
            }
            let diffText = try await service.fetchDiff(presentation.identifier)
            let annotations = Self.annotations(
                threads: pendingThreads,
                staged: presentation.comments,
                detail: detail
            )
            let files = Self.commentedFiles(
                in: DiffParser.parse(diffText),
                anchors: Array(annotations.threads.keys)
            )
            let shown = Array(files.prefix(PullRequestReviewProposalPreview.maximumFiles))
            return .loaded(
                PullRequestReviewProposalPreview(
                    files: shown,
                    annotations: annotations,
                    pendingCommentCount: pendingThreads.reduce(0) { $0 + $1.comments.count },
                    proposedCommentCount: presentation.comments.count,
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
    /// Narrows to the files a comment sits on, and inside each to the hunks holding one.
    static func commentedFiles(
        in files: [DiffFile],
        anchors: [DiffCommentAnchor]
    ) -> [DiffFile] {
        var anchorsByPath: [String: Set<Int>] = [:]
        for anchor in anchors {
            anchorsByPath[anchor.path, default: []].insert(anchor.line)
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
    /// so nothing on it can post to GitHub before the user confirms. The proposal's staged
    /// comments join the server draft's threads, attributed to the viewer — a staged comment on an
    /// already-drafted line appends to that thread rather than opening a second card on the line.
    static func annotations(
        threads: [PullRequestReviewThread],
        staged: [PullRequestReviewProposalRecord.Comment],
        detail: PullRequestDetail
    ) -> DiffCommentAnnotations {
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
        for comment in staged {
            let anchor = DiffCommentAnchor(
                path: comment.path,
                side: DiffCommentAnchor.Side(rawValue: comment.side) ?? .right,
                line: comment.line
            )
            let lineComment = DiffLineComment(
                author: detail.viewerLogin ?? "You",
                bodyMarkdown: PullRequestMarkdown.sanitized(comment.body),
                isPending: false,
                avatarURL: detail.viewerAvatarURL,
                isProposed: true
            )
            if var existing = annotations.threads[anchor] {
                existing.comments.append(lineComment)
                annotations.threads[anchor] = existing
            } else {
                annotations.threads[anchor] = DiffLineCommentThread(comments: [lineComment])
            }
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
