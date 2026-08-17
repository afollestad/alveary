import Foundation

/// A review submission awaiting the user's confirmation in the conversation that proposed it.
///
/// Stored as a JSON envelope on `Conversation` rather than a `@Model`: the invariant is already one
/// pending proposal per conversation, and a new model with a `Conversation` inverse would have to be
/// registered in every `ModelContainer` the app and its tests build. It cascades with the
/// conversation for free. The transcript widget and the pull request pane both read and edit it.
struct PullRequestReviewProposalRecord: Codable, Equatable, Sendable {
    /// Version 2 added `comments`; version 3 added each comment's anchor fingerprint. Decode
    /// accepts older versions — a v1 envelope simply carries no comments, a v2 one no fingerprints
    /// — but each field's presence still demands the bump: an envelope read as an older version
    /// would confirm-submit something other than what the card showed, so an older build must
    /// refuse it outright.
    static let currentPayloadVersion = 3

    /// One staged inline comment, published only when the user confirms. `side` stores the
    /// wire value (`RIGHT`/`LEFT`) so the envelope does not depend on an app enum's cases.
    struct Comment: Codable, Equatable, Sendable {
        let path: String
        let line: Int
        let side: String
        let body: String
        /// The anchored line's exact text as the diff read at propose time, and a symmetric window
        /// of the lines around it.
        ///
        /// These exist so a comment whose line moved can be relocated instead of silently dropped:
        /// `ReviewProposalAnchorResolution` matches the content against the current diff, using the
        /// window to break ties. They live here rather than in
        /// `PullRequestReviewProposalPreviewCache` because that cache is overwritten with freshly
        /// parsed hunks on every successful refresh — by the time an anchor is noticed stale, it
        /// already holds the *new* diff, and the staged-at content is gone.
        ///
        /// Both are nil in envelopes written before version 3, and in comments a person composed in
        /// the pane rather than a tool call. A comment without them cannot relocate.
        let anchorContent: String?
        let anchorContext: [String]?

        init(
            path: String,
            line: Int,
            side: String,
            body: String,
            anchorContent: String? = nil,
            anchorContext: [String]? = nil
        ) {
            self.path = path
            self.line = line
            self.side = side
            self.body = body
            self.anchorContent = anchorContent
            self.anchorContext = anchorContext
        }
    }

    let payloadVersion: Int
    let id: String
    let deduplicationKey: String
    let repositoryNameWithOwner: String
    let number: Int
    /// The tool-facing event name (`approve`, `request_changes`, `comment`). The user may pick a
    /// different verdict when confirming; this is what the model asked for.
    let event: String
    let body: String?
    /// The review's inline comments, staged locally — nothing exists on GitHub until the user
    /// confirms. Nil in envelopes written before version 2.
    let comments: [Comment]?
    /// Snapshotted so the card can name the pull request without a fetch. The pending review's
    /// node id is deliberately *not* snapshotted — it is resolved fresh at confirmation.
    let titleSnapshot: String
    let pendingCommentCountSnapshot: Int
    let sourceProviderID: String?
    let sourceProcessToken: String
    let sourceRequestID: String
    let createdAt: Date

    var identifier: PullRequestIdentifier? {
        PullRequestIdentifier(nameWithOwner: repositoryNameWithOwner, number: number)
    }

    var displayKey: String {
        "\(repositoryNameWithOwner)#\(number)"
    }

    var stagedComments: [Comment] {
        comments ?? []
    }

    /// The envelope with one staged comment dropped, for the per-comment Remove. Returns nil for an
    /// out-of-range index rather than rewriting the envelope with nothing changed.
    func removingComment(at index: Int) -> PullRequestReviewProposalRecord? {
        var remaining = stagedComments
        guard remaining.indices.contains(index) else {
            return nil
        }
        remaining.remove(at: index)
        return replacingComments(remaining)
    }

    /// The envelope with one more staged comment, for a comment composed in the pull request pane
    /// while this proposal is pending. Appending rather than inserting keeps every existing
    /// position stable, which is what lets a rendered card's Remove keep addressing the comment it
    /// shows — position is the only identity a staged comment has.
    func appendingComment(_ comment: Comment) -> PullRequestReviewProposalRecord {
        replacingComments(stagedComments + [comment])
    }

    /// An emptied list normalizes back to `nil`, matching how a comment-free proposal is written at
    /// creation. `payloadVersion` deliberately does not move: the shape is unchanged, and an older
    /// build reading the result would submit exactly what its card shows — the condition the version
    /// guard exists for.
    private func replacingComments(_ comments: [Comment]) -> PullRequestReviewProposalRecord {
        PullRequestReviewProposalRecord(
            payloadVersion: payloadVersion,
            id: id,
            deduplicationKey: deduplicationKey,
            repositoryNameWithOwner: repositoryNameWithOwner,
            number: number,
            event: event,
            body: body,
            comments: comments.isEmpty ? nil : comments,
            titleSnapshot: titleSnapshot,
            pendingCommentCountSnapshot: pendingCommentCountSnapshot,
            sourceProviderID: sourceProviderID,
            sourceProcessToken: sourceProcessToken,
            sourceRequestID: sourceRequestID,
            createdAt: createdAt
        )
    }
}

extension Notification.Name {
    /// A review proposal was opened, confirmed, rejected, or superseded.
    static let pullRequestReviewProposalsChanged = Notification.Name("pullRequestReviewProposalsChanged")
    /// Card-only state moved: the picked verdict, the diff preview, or the submitting flag.
    /// Separate from the lifecycle notification because that one also triggers transcript
    /// rebuilds, which a picker click must not pay for.
    static let reviewProposalCardStateChanged = Notification.Name("reviewProposalCardStateChanged")
}

enum PullRequestReviewProposalStorageError: Error, Equatable {
    case invalidPayload
    case unsupportedPayloadVersion(Int)
    case encodingFailed
}

extension Conversation {
    /// Throws rather than returning nil for an unreadable envelope: a proposal Alveary cannot
    /// understand must not be silently replaced by a second one the user never saw agreed.
    func pullRequestReviewProposal() throws -> PullRequestReviewProposalRecord? {
        guard let pullRequestReviewProposalJSON else {
            return nil
        }
        guard let data = pullRequestReviewProposalJSON.data(using: .utf8) else {
            throw PullRequestReviewProposalStorageError.invalidPayload
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record: PullRequestReviewProposalRecord
        do {
            record = try decoder.decode(PullRequestReviewProposalRecord.self, from: data)
        } catch {
            throw PullRequestReviewProposalStorageError.invalidPayload
        }
        // Older versions decode — optional fields added since simply read nil. Only a *newer*
        // envelope is refused: it may carry fields this build would silently drop, and a confirm
        // must never submit less than the card showed.
        guard record.payloadVersion <= PullRequestReviewProposalRecord.currentPayloadVersion else {
            throw PullRequestReviewProposalStorageError.unsupportedPayloadVersion(record.payloadVersion)
        }
        return record
    }

    func storePullRequestReviewProposal(_ record: PullRequestReviewProposalRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw PullRequestReviewProposalStorageError.encodingFailed
        }
        pullRequestReviewProposalJSON = encoded
    }

    /// Clearing never decodes, so an envelope this build cannot read is still dismissible.
    func clearPullRequestReviewProposal() {
        pullRequestReviewProposalJSON = nil
    }
}
