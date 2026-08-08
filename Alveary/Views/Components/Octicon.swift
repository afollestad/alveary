import Foundation

/// The vendored Primer Octicons, named once so call sites cannot invent an
/// asset string. Asset lookup fails *silently* — SwiftUI's `Image` draws
/// nothing and `NSImage(named:)` returns nil, neither of which is a compile
/// error — so a typo or a renamed imageset would otherwise ship as a blank
/// glyph. `OcticonAssetTests` closes the remaining gap by resolving every case.
///
/// The case suffix is the artwork's **canvas**, not the size it renders at.
/// Prefer `16` beside SF Symbols, whose strokes it matches; `24` artwork reads
/// visibly thinner at the same frame. The asset names do not encode this
/// consistently — `FileDiffOcticon` is 16px artwork despite the bare name — so
/// the cases do it instead.
enum Octicon: String, CaseIterable {
    case alert16 = "AlertOcticon16"
    case checkCircle16 = "CheckCircleOcticon16"
    case codeReview16 = "CodeReviewOcticon16"
    case comment16 = "CommentOcticon16"
    case dash24 = "DashOcticon"
    case eye24 = "EyeOcticon"
    case fileDiff16 = "FileDiffOcticon"
    case gitBranch16 = "GitBranchOcticon16"
    case gitCommit24 = "GitCommitOcticon"
    case plus24 = "PlusOcticon"
    case pullRequest16 = "PullRequestOcticon16"
    case pullRequest24 = "PullRequestOcticon"
    case pullRequestClosed16 = "PullRequestClosedOcticon16"
    case pullRequestClosed24 = "PullRequestClosedOcticon"
    case pullRequestDraft16 = "PullRequestDraftOcticon16"
    case pullRequestDraft24 = "PullRequestDraftOcticon"
    case pullRequestMerge16 = "PullRequestMergeOcticon16"
    case pullRequestMerge24 = "PullRequestMergeOcticon"
    case reply16 = "ReplyOcticon16"
    case repoPush16 = "RepoPushOcticon16"

    /// The asset-catalog name. Reach for this only where the image is actually
    /// loaded — `OcticonImage` and the `NSImage(named:)` calls in AppKit views —
    /// never to pass a glyph around as a string.
    var assetName: String { rawValue }
}
