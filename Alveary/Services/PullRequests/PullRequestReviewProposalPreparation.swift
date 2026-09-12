import Foundation
import SwiftData

/// Shared preparation and persistence for host-created and app-created proposals; neither path submits to GitHub.
enum PullRequestReviewProposalPreparation {
    static func seedPreview(
        cache: PullRequestReviewProposalPreviewCache?, record: PullRequestReviewProposalRecord,
        detail: PullRequestDetail, files: [DiffFile]?, at date: Date
    ) async {
        guard let cache, let identifier = record.identifier else { return }
        // A summary-only proposal must not seed an empty preview over the user's existing GitHub draft.
        guard files != nil || detail.pendingCommentCount == 0 else { return }
        let narrowed = ReviewProposalDiffNarrowing.narrowed(
            files: files ?? [], linesByPath: ReviewProposalDiffNarrowing.linesByPath(for: record.stagedComments)
        )
        let shown = Array(narrowed.prefix(ReviewProposalDiffNarrowing.maximumFiles))
        await cache.save(PullRequestReviewProposalPreviewCache.Entry(
            identifier: identifier, files: shown, hiddenFileCount: narrowed.count - shown.count,
            viewerLogin: detail.viewerLogin, viewerAvatarURL: detail.viewerAvatarURL,
            viewerIsAuthor: detail.viewerLogin.map { $0 == detail.authorLogin } ?? false, fetchedAt: date
        ), forProposalID: record.id)
    }

    /// The caller flushes unrelated edits first. The receipt and envelope must commit together, with no suspension.
    @MainActor
    static func commit(
        in context: ModelContext, save: (ModelContext) throws -> Void = { try $0.save() },
        restoringOnFailure restore: () -> Void = {},
        changes: () throws -> Void
    ) throws {
        do {
            try changes()
            try save(context)
        } catch {
            context.processPendingChanges()
            restore()
            context.processPendingChanges()
            context.rollback()
            throw error
        }
    }
}
