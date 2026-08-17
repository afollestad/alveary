import Foundation

/// Persists the narrowed diff hunks a review-proposal card draws, so the transcript paints a
/// complete card instead of a loading caption while two `gh` round trips run behind it. Load
/// failures are treated as a cold cache — never as errors — which is also what retires an older
/// file shape: it simply fails to decode.
///
/// Only the hunks are cached, because only they cost the network. A proposal's own comments already
/// live in the conversation's envelope, and the viewer's GitHub-side pending draft threads are
/// server state the background refresh folds in — caching those would paint a stale draft as
/// current.
actor PullRequestReviewProposalPreviewCache {
    /// One proposal's cached hunks, plus the viewer identity its staged comments are attributed to.
    ///
    /// `identifier` is stored so an entry can be rejected when the proposal it keys has been
    /// superseded by one against a different pull request; the id alone would let those hunks paint
    /// under the wrong review.
    struct Entry: Codable, Equatable, Sendable {
        let identifier: PullRequestIdentifier
        /// Already narrowed to commented hunks and capped at `ReviewProposalDiffNarrowing.maximumFiles`.
        let files: [DiffFile]
        /// Files carrying comments that the cap dropped.
        let hiddenFileCount: Int
        let viewerLogin: String?
        let viewerAvatarURL: URL?
        let viewerIsAuthor: Bool
        let fetchedAt: Date
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Every cached entry, keyed by proposal id. Empty when there is nothing usable to paint.
    func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? decoder.decode([String: Entry].self, from: data) else {
            return [:]
        }
        return entries
    }

    func save(_ entry: Entry, forProposalID proposalID: String) {
        var entries = load()
        entries[proposalID] = entry
        write(entries)
    }

    /// Drops entries for proposals that are no longer pending, so a confirmed or cancelled review
    /// cannot leave its diff on disk indefinitely.
    func prune(keepingProposalIDs proposalIDs: Set<String>) {
        let entries = load()
        let kept = entries.filter { proposalIDs.contains($0.key) }
        guard kept.count != entries.count else {
            return
        }
        write(kept)
    }

    private func write(_ entries: [String: Entry]) {
        guard let data = try? encoder.encode(entries) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}
