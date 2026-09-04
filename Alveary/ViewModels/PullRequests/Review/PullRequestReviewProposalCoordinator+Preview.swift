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
    /// sends the rest to the pull request pane. Shared with propose time, which seeds the preview
    /// cache and has to cap it identically or the card would re-flow when the refresh landed.
    static let maximumFiles = ReviewProposalDiffNarrowing.maximumFiles

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
    /// Staged comments the current diff cannot place, by their position in the envelope.
    ///
    /// These are reported rather than dropped. The narrowing that builds `files` walks lines asking
    /// which carries a comment, so an anchor matching nothing disappears without a trace — leaving
    /// the card promising a count it does not draw, and a confirm that fails partway through.
    let staleComments: [StaleComment]
    /// GitHub refuses approve and request-changes on the viewer's own pull request, so the card's
    /// verdict picker disables them.
    let viewerIsAuthor: Bool

    /// One unplaceable staged comment. Carries the path but no line, matching how the pane names an
    /// outdated thread whose anchor GitHub no longer reports.
    struct StaleComment: Equatable {
        let proposedIndex: Int
        let path: String
        let bodyMarkdown: String
    }
}

/// A preview load's two results: what the card renders now, and what the cache keeps for next time.
///
/// The cached files are narrowed to the proposal's *own* staged comments rather than to everything
/// the card drew. The viewer's GitHub-side draft threads are server state, and a cached paint that
/// reproduced them would show a draft that may since have been submitted or discarded — so the
/// entry stays "the hunks this proposal's comments sit on" whatever else the refresh folded in.
struct PullRequestReviewProposalPreviewLoad {
    let state: PullRequestReviewProposalPreviewState
    /// Nil when the load failed, so a failure never overwrites a good entry.
    let cacheEntry: PullRequestReviewProposalPreviewCache.Entry?
}

extension PullRequestReviewProposalCoordinator {
    /// Context lines kept around a commented hunk are the hunk's own — whole hunks only, so line
    /// numbers stay meaningful.
    func loadPreview(
        for presentation: PullRequestReviewProposalPresentation
    ) async -> PullRequestReviewProposalPreviewLoad {
        do {
            let detail = try await service.fetchDetail(presentation.identifier)
            let pendingThreads = detail.reviewThreads.filter { $0.isPending && $0.line != nil }
            let viewerIsAuthor = detail.viewerLogin.map { $0 == detail.authorLogin } ?? false
            guard !pendingThreads.isEmpty || !presentation.comments.isEmpty else {
                // A summary-only review has no comments to show; the card renders its body alone.
                return PullRequestReviewProposalPreviewLoad(
                    state: .loaded(
                        PullRequestReviewProposalPreview(
                            files: [],
                            annotations: DiffCommentAnnotations(),
                            pendingCommentCount: 0,
                            proposedCommentCount: 0,
                            hiddenFileCount: 0,
                            staleComments: [],
                            viewerIsAuthor: viewerIsAuthor
                        )
                    ),
                    cacheEntry: Self.entry(
                        for: presentation,
                        detail: detail,
                        files: [],
                        hiddenFileCount: 0,
                        fetchedAt: currentDate
                    )
                )
            }
            let paths = Set(presentation.comments.map(\.path) + pendingThreads.map(\.path))
            let parsed = try await service.fetchDiffFiles(presentation.identifier, paths: paths)
            return commentedLoad(
                for: presentation,
                detail: detail,
                pendingThreads: pendingThreads,
                parsed: parsed,
                viewerIsAuthor: viewerIsAuthor
            )
        } catch {
            return PullRequestReviewProposalPreviewLoad(
                state: .failed(Self.previewMessage(for: error)),
                cacheEntry: nil
            )
        }
    }

    /// Shapes a parsed diff into what the card draws and what the cache keeps.
    ///
    /// The two narrowings differ on purpose: the card shows every commented hunk, the entry only
    /// the proposal's own — see `PullRequestReviewProposalPreviewLoad`.
    private func commentedLoad(
        for presentation: PullRequestReviewProposalPresentation,
        detail: PullRequestDetail,
        pendingThreads: [PullRequestReviewThread],
        parsed: [DiffFile],
        viewerIsAuthor: Bool
    ) -> PullRequestReviewProposalPreviewLoad {
        var stale: [PullRequestReviewProposalPreview.StaleComment] = []
        let annotations = Self.annotations(
            threads: pendingThreads,
            staged: presentation.comments,
            detail: detail,
            files: parsed,
            stale: &stale
        )
        let files = Self.commentedFiles(in: parsed, anchors: Array(annotations.threads.keys))
        let shown = Array(files.prefix(PullRequestReviewProposalPreview.maximumFiles))
        // Resolved lines, not stored ones: a relocated comment's hunk lives at its new line, and
        // an entry narrowed by the old one would omit it — the next launch's cached paint would
        // then claim the comment cannot be placed until the refresh corrected it.
        let stagedFiles = ReviewProposalDiffNarrowing.narrowed(
            files: parsed,
            linesByPath: ReviewProposalAnchorResolution.resolvedLinesByPath(
                presentation.comments,
                against: parsed
            )
        )
        let cachedFiles = Array(stagedFiles.prefix(PullRequestReviewProposalPreview.maximumFiles))
        return PullRequestReviewProposalPreviewLoad(
            state: .loaded(
                PullRequestReviewProposalPreview(
                    files: shown,
                    annotations: annotations,
                    pendingCommentCount: pendingThreads.reduce(0) { $0 + $1.comments.count },
                    proposedCommentCount: presentation.comments.count,
                    hiddenFileCount: files.count - shown.count,
                    staleComments: stale,
                    viewerIsAuthor: viewerIsAuthor
                )
            ),
            cacheEntry: Self.entry(
                for: presentation,
                detail: detail,
                files: cachedFiles,
                hiddenFileCount: stagedFiles.count - cachedFiles.count,
                fetchedAt: currentDate
            )
        )
    }
}

extension PullRequestReviewProposalCoordinator {
    /// The card's preview rebuilt from cached hunks, with no network at all.
    ///
    /// The comments come from the live envelope rather than from the entry, and the hunks are
    /// re-narrowed against them, so a comment staged or removed since the entry was written is
    /// reflected on the first paint. `pendingCommentCount` is the envelope's snapshot because the
    /// viewer's own GitHub-side draft threads are deliberately not cached; the refresh running
    /// behind this paint is what folds the real ones in.
    static func preview(
        from entry: PullRequestReviewProposalPreviewCache.Entry,
        presentation: PullRequestReviewProposalPresentation
    ) -> PullRequestReviewProposalPreview {
        var annotations = DiffCommentAnnotations()
        annotations.allowsComposing = false
        let stale = appendStagedComments(
            presentation.comments,
            to: &annotations,
            resolvedAgainst: entry.files,
            viewerLogin: entry.viewerLogin,
            viewerAvatarURL: entry.viewerAvatarURL
        )
        return PullRequestReviewProposalPreview(
            files: commentedFiles(in: entry.files, anchors: Array(annotations.threads.keys)),
            annotations: annotations,
            pendingCommentCount: presentation.pendingCommentCount,
            proposedCommentCount: presentation.comments.count,
            hiddenFileCount: entry.hiddenFileCount,
            staleComments: stale,
            viewerIsAuthor: entry.viewerIsAuthor
        )
    }

    /// The loaded preview with one staged comment pruned out, so removing a comment costs no
    /// network. Removal only ever subtracts, so the already-loaded preview can be narrowed in
    /// place — refetching would cost a `fetchDetail` plus `fetchDiff` round trip and a loading
    /// flash on a click, and retaining the parsed diff to re-derive from is exactly the memory the
    /// coordinator drops on purpose.
    ///
    /// Two consequences worth knowing:
    /// - Every surviving `proposedIndex` above the removed one shifts down, because the envelope's
    ///   array did; without that the next Remove would address the wrong comment.
    /// - `hiddenFileCount` does not shrink. Revealing a file the `maximumFiles` cap hid needs the
    ///   full parsed diff, so "N more files not shown" stays truthful but not maximal.
    static func preview(
        _ preview: PullRequestReviewProposalPreview,
        removingProposedCommentAt index: Int
    ) -> PullRequestReviewProposalPreview {
        var annotations = preview.annotations
        var removed = false
        for (anchor, thread) in annotations.threads {
            var comments: [DiffLineComment] = []
            for comment in thread.comments {
                guard let proposedIndex = comment.proposedIndex else {
                    comments.append(comment)
                    continue
                }
                if proposedIndex == index {
                    removed = true
                    continue
                }
                var survivor = comment
                if proposedIndex > index {
                    survivor.proposedIndex = proposedIndex - 1
                }
                comments.append(survivor)
            }
            guard !comments.isEmpty else {
                annotations.threads[anchor] = nil
                continue
            }
            var updated = thread
            updated.comments = comments
            annotations.threads[anchor] = updated
        }
        let stale = staleComments(preview.staleComments, removingProposedCommentAt: index)
        guard removed || stale.count != preview.staleComments.count else {
            return preview
        }
        return PullRequestReviewProposalPreview(
            files: commentedFiles(in: preview.files, anchors: Array(annotations.threads.keys)),
            annotations: annotations,
            pendingCommentCount: preview.pendingCommentCount,
            proposedCommentCount: max(preview.proposedCommentCount - 1, 0),
            hiddenFileCount: preview.hiddenFileCount,
            staleComments: stale,
            viewerIsAuthor: preview.viewerIsAuthor
        )
    }
}

extension PullRequestReviewProposalCoordinator {
    /// Merges a proposal's staged comments into diff annotations, attributed to the viewer and
    /// tagged with each comment's position in the stored envelope.
    ///
    /// Shared by the transcript card's own preview and the pull request pane's Changes tab, which
    /// render the same review from the same envelope and must not drift. A staged comment on a line
    /// that already carries a thread appends to it rather than opening a second card on the line.
    ///
    /// `proposedIndex` is the only identity a staged comment has, so it is what a Remove addresses;
    /// every removal shifts the array, which is why a pruned preview renumbers what survives. A
    /// comment the diff cannot place keeps its index and is *returned* rather than annotated —
    /// dropping it here is what let the card promise a count it did not draw.
    ///
    /// Resolution happens inside this function rather than at each call site precisely because
    /// those sites must not drift: a comment relocated on the transcript card and left at its stale
    /// line in the pane would be two different reviews.
    @discardableResult
    static func appendStagedComments(
        _ staged: [PullRequestReviewProposalRecord.Comment],
        to annotations: inout DiffCommentAnnotations,
        resolvedAgainst files: [DiffFile],
        viewerLogin: String?,
        viewerAvatarURL: URL?
    ) -> [PullRequestReviewProposalPreview.StaleComment] {
        var stale: [PullRequestReviewProposalPreview.StaleComment] = []
        let lines = ReviewProposalAnchorResolution.resolvedLines(staged, against: files)
        for (index, comment) in staged.enumerated() {
            let body = PullRequestMarkdown.sanitized(comment.body)
            guard let line = lines[index] else {
                stale.append(
                    PullRequestReviewProposalPreview.StaleComment(
                        proposedIndex: index,
                        path: comment.path,
                        bodyMarkdown: body
                    )
                )
                continue
            }
            let anchor = DiffCommentAnchor(
                path: comment.path,
                side: DiffCommentAnchor.Side(rawValue: comment.side) ?? .right,
                line: line
            )
            let lineComment = DiffLineComment(
                author: viewerLogin ?? "You",
                bodyMarkdown: body,
                isPending: false,
                avatarURL: viewerAvatarURL,
                proposedIndex: index
            )
            if var existing = annotations.threads[anchor] {
                existing.comments.append(lineComment)
                annotations.threads[anchor] = existing
            } else {
                annotations.threads[anchor] = DiffLineCommentThread(comments: [lineComment])
            }
        }
        return stale
    }

    /// The same staged comments as review threads, for the Overview timeline — which renders
    /// GitHub's own threads and needs these to read the same way.
    ///
    /// Built at render time and never written into `PullRequestDetail.reviewThreads`: that array
    /// is what exists on GitHub, and a synthetic entry there would reach every path that trusts
    /// it, `pendingCommentCount` and the submit gates included.
    ///
    /// Comments sharing an anchor become one thread, matching how the diff merges them.
    static func stagedThreads(
        _ staged: [PullRequestReviewProposalRecord.Comment],
        viewerLogin: String?,
        viewerAvatarURL: URL?,
        createdAt: Date
    ) -> [PullRequestReviewThread] {
        var threads: [PullRequestReviewThread] = []
        var indexByAnchor: [DiffCommentAnchor: Int] = [:]
        for (index, comment) in staged.enumerated() {
            let side: PullRequestDiffSide = comment.side == PullRequestDiffSide.left.rawValue ? .left : .right
            let anchor = DiffCommentAnchor(
                path: comment.path,
                side: side == .left ? .left : .right,
                line: comment.line
            )
            let rendered = PullRequestComment(
                authorLogin: viewerLogin ?? "You",
                authorAvatarURL: viewerAvatarURL,
                bodyMarkdown: PullRequestMarkdown.sanitized(comment.body),
                createdAt: createdAt,
                proposedIndex: index
            )
            if let existing = indexByAnchor[anchor] {
                threads[existing].comments.append(rendered)
                continue
            }
            indexByAnchor[anchor] = threads.count
            threads.append(
                PullRequestReviewThread(
                    path: comment.path,
                    line: comment.line,
                    side: side,
                    isResolved: false,
                    isOutdated: false,
                    comments: [rendered]
                )
            )
        }
        return threads
    }
}

private extension PullRequestReviewProposalCoordinator {
    /// Stale comments hold envelope positions too, so a removal shifts them by the rule that shifts
    /// every annotated one — and the removed comment may itself be stale, which is the only way to
    /// clear one from the card.
    static func staleComments(
        _ comments: [PullRequestReviewProposalPreview.StaleComment],
        removingProposedCommentAt index: Int
    ) -> [PullRequestReviewProposalPreview.StaleComment] {
        comments.filter { $0.proposedIndex != index }.map { comment in
            PullRequestReviewProposalPreview.StaleComment(
                proposedIndex: comment.proposedIndex > index
                    ? comment.proposedIndex - 1
                    : comment.proposedIndex,
                path: comment.path,
                bodyMarkdown: comment.bodyMarkdown
            )
        }
    }

    /// Narrows to the files a comment sits on, and inside each to the hunks holding one.
    static func commentedFiles(
        in files: [DiffFile],
        anchors: [DiffCommentAnchor]
    ) -> [DiffFile] {
        ReviewProposalDiffNarrowing.narrowed(
            files: files,
            linesByPath: anchors.reduce(into: [String: Set<Int>]()) { result, anchor in
                result[anchor.path, default: []].insert(anchor.line)
            }
        )
    }

    /// What the cache keeps for a proposal, given the diff this load parsed.
    static func entry(
        for presentation: PullRequestReviewProposalPresentation,
        detail: PullRequestDetail,
        files: [DiffFile],
        hiddenFileCount: Int,
        fetchedAt: Date
    ) -> PullRequestReviewProposalPreviewCache.Entry {
        PullRequestReviewProposalPreviewCache.Entry(
            identifier: presentation.identifier,
            files: files,
            hiddenFileCount: hiddenFileCount,
            viewerLogin: detail.viewerLogin,
            viewerAvatarURL: detail.viewerAvatarURL,
            viewerIsAuthor: detail.viewerLogin.map { $0 == detail.authorLogin } ?? false,
            fetchedAt: fetchedAt
        )
    }

    /// Inert annotations: the card renders threads read-only, with no composer and no interaction,
    /// so nothing on it can post to GitHub before the user confirms. The proposal's staged
    /// comments join the server draft's threads, attributed to the viewer — a staged comment on an
    /// already-drafted line appends to that thread rather than opening a second card on the line.
    static func annotations(
        threads: [PullRequestReviewThread],
        staged: [PullRequestReviewProposalRecord.Comment],
        detail: PullRequestDetail,
        files: [DiffFile],
        stale: inout [PullRequestReviewProposalPreview.StaleComment]
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
        stale = appendStagedComments(
            staged,
            to: &annotations,
            resolvedAgainst: files,
            viewerLogin: detail.viewerLogin,
            viewerAvatarURL: detail.viewerAvatarURL
        )
        return annotations
    }

    static func previewMessage(for error: Error) -> String {
        guard let serviceError = error as? PullRequestsServiceError else {
            return error.localizedDescription
        }
        return serviceError.errorDescription ?? serviceError.localizedDescription
    }
}
