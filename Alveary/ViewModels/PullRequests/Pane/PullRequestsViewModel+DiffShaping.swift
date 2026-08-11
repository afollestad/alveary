import Foundation

// How much of a pull request's diff the Changes tab renders: the whole-file paging window and
// per-file collapse. `PullRequestDiffFilePaging` owns the policy; this is the session state it
// applies to. See `PullRequestsViewModel+ReviewProposalAttachment.swift` for the reveal that
// walks the same two knobs to make one comment's line reachable.
extension PullRequestsViewModel {
    func showMoreDiffFiles() {
        guard let files = activePaneSession?.diffFiles else {
            return
        }
        mutateActiveSession { session in
            session.renderedDiffFileCount = PullRequestDiffFilePaging.nextRenderedFileCount(
                current: session.renderedDiffFileCount,
                total: files.count
            )
        }
    }

    func toggleDiffFileCollapse(_ fileID: String) {
        mutateActiveSession { session in
            if session.collapsedDiffFileIDs.contains(fileID) {
                session.collapsedDiffFileIDs.remove(fileID)
            } else {
                session.collapsedDiffFileIDs.insert(fileID)
            }
        }
    }
}
