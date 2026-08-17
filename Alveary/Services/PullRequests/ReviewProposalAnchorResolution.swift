import Foundation

/// Where a proposal's staged comments sit in the diff *now*.
///
/// A comment is anchored to a line number validated once, at propose time. New commits move those
/// lines, and a stale anchor is not a display problem: `addPendingReviewComment` refuses it, which
/// used to fail partway through confirming and leave a half-written private draft on GitHub.
///
/// So a comment relocates itself when the line it was written against can still be found
/// unambiguously, and is reported as stale when it cannot. Relocation is deliberately conservative
/// — publishing review feedback onto unrelated code is worse than saying a comment needs attention.
enum ReviewProposalAnchorResolution {
    /// Lines of context kept on each side of the anchor, and required to match when several lines
    /// carry the same text. Three is enough to separate repeated one-liners like `}` or `return nil`
    /// without pinning the comment to code far enough away to have changed for unrelated reasons.
    static let contextRadius = 3

    enum Resolution: Equatable {
        /// The stored anchor still resolves; publish it as written.
        case unchanged(line: Int)
        /// The anchored content moved; publish `line` instead of what the envelope stores.
        case relocated(from: Int, line: Int)
        /// Nothing in the current diff matches. The card reports it and confirm refuses it.
        case stale
    }

    /// Resolved in envelope order, so a result can be zipped against `stagedComments` and an index
    /// still addresses the comment a rendered card's Remove would drop.
    static func resolve(
        _ comments: [PullRequestReviewProposalRecord.Comment],
        against files: [DiffFile]
    ) -> [Resolution] {
        // Only commented paths: the pane runs this while building its Changes tab, against the
        // whole pull request's diff, so flattening every file would allocate per render for lookups
        // nothing makes.
        let commentedPaths = Set(comments.map(\.path))
        let linesByPath = Dictionary(
            files.filter { commentedPaths.contains($0.path) }
                .map { ($0.path, $0.hunks.flatMap(\.lines)) },
            uniquingKeysWith: { $0 + $1 }
        )
        return comments.map { resolve($0, against: linesByPath[$0.path] ?? []) }
    }

    /// What a staged comment records about the line it was written against, so a later diff can
    /// relocate it. Nil when the anchor names no line the diff draws — propose time refuses such a
    /// comment anyway, and a person's pane-composed comment simply stores nothing.
    ///
    /// Capture and comparison share `window(around:in:)`, so a comment near a hunk boundary still
    /// matches itself once the surrounding lines shift.
    static func fingerprint(
        path: String,
        line: Int,
        side: DiffCommentAnchor.Side,
        in files: [DiffFile]
    ) -> (content: String, context: [String])? {
        let lines = files.filter { $0.path == path }.flatMap { $0.hunks.flatMap(\.lines) }
        let target = DiffCommentAnchor(path: path, side: side, line: line)
        guard let index = lines.indices.first(where: {
            FlattenedDiffPreviewRows.commentAnchor(for: lines[$0], path: path) == target
        }) else {
            return nil
        }
        return (lines[index].content, window(around: index, in: lines))
    }

    /// The resolved lines keyed by path, in the shape `ReviewProposalDiffNarrowing.narrowed`
    /// indexes by. An unplaceable comment contributes nothing.
    ///
    /// This — not the stored lines — is what narrowing for the preview cache must use: a relocated
    /// comment's hunk is at its *new* line, and an entry narrowed by the old one would omit it,
    /// leaving the next launch's cached paint claiming the comment cannot be placed.
    static func resolvedLinesByPath(
        _ comments: [PullRequestReviewProposalRecord.Comment],
        against files: [DiffFile]
    ) -> [String: Set<Int>] {
        zip(comments, resolvedLines(comments, against: files))
            .reduce(into: [String: Set<Int>]()) { result, pair in
                guard let line = pair.1 else {
                    return
                }
                result[pair.0.path, default: []].insert(line)
            }
    }

    /// The line each comment should publish against, or nil when it cannot be placed.
    static func resolvedLines(
        _ comments: [PullRequestReviewProposalRecord.Comment],
        against files: [DiffFile]
    ) -> [Int?] {
        resolve(comments, against: files).map { resolution in
            switch resolution {
            case .unchanged(let line):
                return line
            case .relocated(_, let line):
                return line
            case .stale:
                return nil
            }
        }
    }
}

private extension ReviewProposalAnchorResolution {
    static func resolve(
        _ comment: PullRequestReviewProposalRecord.Comment,
        against lines: [DiffLine]
    ) -> Resolution {
        let side = DiffCommentAnchor.Side(rawValue: comment.side) ?? .right
        let anchors = lines.map { FlattenedDiffPreviewRows.commentAnchor(for: $0, path: comment.path) }
        let target = DiffCommentAnchor(path: comment.path, side: side, line: comment.line)
        let stored = anchors.firstIndex(of: target)
        guard let content = comment.anchorContent else {
            // Nothing to match on, so the stored anchor is all there is — which is what confirming
            // did before fingerprints existed.
            return stored == nil ? .stale : .unchanged(line: comment.line)
        }
        // Content at the stored line, not merely a line at that number. Inserting a line above
        // leaves the old number occupied by *different* code, and treating that as unchanged is
        // precisely how a comment ends up published against something it was not written about.
        if let stored, lines[stored].content == content {
            return .unchanged(line: comment.line)
        }
        // Only positions the pane could draw: matching a line whose own anchor is on the other side
        // would publish a LEFT comment onto a RIGHT-anchored line, which renders nowhere.
        let candidates = lines.indices.filter { index in
            lines[index].content == content && anchors[index]?.side == side
        }
        guard let match = disambiguate(candidates, in: lines, using: comment.anchorContext),
              let anchor = anchors[match] else {
            return .stale
        }
        return anchor.line == comment.line
            ? .unchanged(line: anchor.line)
            : .relocated(from: comment.line, line: anchor.line)
    }

    /// The one candidate whose surroundings match the stored window, or nil when the choice is not
    /// unique. Ambiguity resolves to stale rather than to a guess.
    static func disambiguate(
        _ candidates: [Int],
        in lines: [DiffLine],
        using context: [String]?
    ) -> Int? {
        guard candidates.count > 1 else {
            return candidates.first
        }
        guard let context, !context.isEmpty else {
            return nil
        }
        let matching = candidates.filter { window(around: $0, in: lines) == context }
        return matching.count == 1 ? matching.first : nil
    }

    /// The stored window's shape: `contextRadius` lines each side, clipped at the file's edges.
    /// Capture and comparison share this so a comment near a boundary still matches itself.
    static func window(around index: Int, in lines: [DiffLine]) -> [String] {
        let lower = max(lines.startIndex, index - contextRadius)
        let upper = min(lines.endIndex, index + contextRadius + 1)
        return lines[lower..<upper].enumerated()
            .filter { lower + $0.offset != index }
            .map(\.element.content)
    }
}
