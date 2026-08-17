import Foundation

/// Narrows a parsed diff to the files a review's comments sit on, and inside each to the hunks
/// holding one.
///
/// Shared by the transcript card's preview load and by `propose_pr_review`, which seeds
/// `PullRequestReviewProposalPreviewCache` from the diff it already parsed to validate anchors.
/// One implementation because a seeded entry has to match what a refresh would produce — two
/// narrowings that disagreed would make the card visibly re-flow when the refresh landed.
enum ReviewProposalDiffNarrowing {
    /// A transcript card cannot scroll, so a review spanning many files shows its first few and
    /// sends the rest to the pull request pane.
    static let maximumFiles = 5

    /// `linesByPath` is every commented line, keyed by the file it anchors to.
    static func narrowed(files: [DiffFile], linesByPath: [String: Set<Int>]) -> [DiffFile] {
        files.compactMap { file in
            guard let lines = linesByPath[file.path] else {
                return nil
            }
            let hunks = file.hunks.filter { hunk in
                hunk.lines.contains { line in
                    // A comment anchors on whichever side's number it was written against, so
                    // either side matching keeps the hunk.
                    line.newLineNumber.map(lines.contains) == true
                        || line.oldLineNumber.map(lines.contains) == true
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

    /// The commented lines of a proposal's staged comments, in the shape `narrowed` indexes by.
    static func linesByPath(for comments: [PullRequestReviewProposalRecord.Comment]) -> [String: Set<Int>] {
        comments.reduce(into: [String: Set<Int>]()) { result, comment in
            result[comment.path, default: []].insert(comment.line)
        }
    }
}
