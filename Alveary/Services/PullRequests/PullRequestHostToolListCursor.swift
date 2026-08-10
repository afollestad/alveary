import Foundation

/// A parsed `list_involved_prs` call. These are the values the call actually runs with — on a
/// cursor call they come from the token rather than from the arguments.
struct PullRequestHostToolListRequest: Equatable {
    let filter: PullRequestHostToolListFilter
    let limit: Int
    let status: PullRequestStatus
    let updatedAfter: Date?
    let updatedBefore: Date?
    /// The buckets this call fetches: a first call takes the filter's, a cursor call takes only
    /// the ones the token still has pages for, so a drained bucket costs no GitHub search.
    let buckets: Set<PullRequestInvolvementBucket>
    /// Where each of those buckets resumes. A bucket in `buckets` but absent here restarts at its
    /// first page — what `PullRequestListCursorAdvance` asks for when a page contributed nothing.
    let cursors: [PullRequestInvolvementBucket: String]
}

/// The opaque string `list_involved_prs` returns as `next_cursor` and takes back as `cursor`.
///
/// It carries the whole query rather than only the positions, because a paginating model passes
/// `{cursor}` alone: the call has to reconstruct the filter, status, bounds, and limit it is
/// continuing. An argument passed beside it that *disagrees* is refused rather than merged —
/// either answer would silently be the wrong one, and page 2 of a different search is worse than
/// an error naming the conflict.
struct PullRequestListCursorToken: Equatable {
    /// Bumped when a field a continuation acts on changes shape. An older Alveary refuses a newer
    /// token outright rather than paging with half the query.
    static let currentVersion = 1

    let filter: PullRequestHostToolListFilter
    let limit: Int
    let status: PullRequestStatus
    let updatedAfter: Date?
    let updatedBefore: Date?
    /// The buckets with pages left, in `allCases` order. Empty means the list is drained, and the
    /// handler emits no cursor at all.
    let buckets: [PullRequestInvolvementBucket]
    /// Positions for whichever of `buckets` have one.
    let cursors: [PullRequestInvolvementBucket: String]

    /// Base64url of canonical JSON, so the same query and positions always encode to the same
    /// string and a token stays safe to hand back through JSON arguments.
    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = PullRequestListCursorPayload(
            version: Self.currentVersion,
            filter: filter.rawValue,
            limit: limit,
            status: status.rawValue,
            updatedAfter: updatedAfter.map(PullRequestSearchDates.day),
            updatedBefore: updatedBefore.map(PullRequestSearchDates.day),
            buckets: buckets.map(\.rawValue),
            cursors: Dictionary(uniqueKeysWithValues: cursors.map { ($0.key.rawValue, $0.value) })
        )
        return Self.base64URL(try encoder.encode(payload))
    }

    /// `path` names the argument in the refusal, so the model is told which field to drop.
    static func decoded(from raw: String, path: String) throws -> PullRequestListCursorToken {
        guard let data = base64URLDecoded(raw),
              let payload = try? JSONDecoder().decode(PullRequestListCursorPayload.self, from: data) else {
            throw unreadable(path: path)
        }
        guard payload.version <= currentVersion else {
            throw HostToolRequestError.invalidArguments(
                "\(path).cursor was produced by a newer version of Alveary and cannot be continued here. " +
                    "Call list_involved_prs again without cursor to start over."
            )
        }
        // Every token Alveary mints carries a limit the parser already capped, so one outside
        // those bounds is forged or corrupt — honoring it could emit an oversized result.
        guard let filter = PullRequestHostToolListFilter(rawValue: payload.filter),
              let status = PullRequestStatus(rawValue: payload.status),
              payload.limit > 0,
              payload.limit <= PullRequestHostToolLimits.maxListRows else {
            throw unreadable(path: path)
        }
        let buckets = payload.buckets.compactMap(PullRequestInvolvementBucket.init(rawValue:))
        guard buckets.count == payload.buckets.count else {
            throw unreadable(path: path)
        }
        var cursors: [PullRequestInvolvementBucket: String] = [:]
        for (rawBucket, cursor) in payload.cursors {
            guard let bucket = PullRequestInvolvementBucket(rawValue: rawBucket) else {
                throw unreadable(path: path)
            }
            cursors[bucket] = cursor
        }
        return PullRequestListCursorToken(
            filter: filter,
            limit: payload.limit,
            status: status,
            updatedAfter: try payload.updatedAfter.map { try day($0, path: path) },
            updatedBefore: try payload.updatedBefore.map { try day($0, path: path) },
            buckets: buckets,
            cursors: cursors
        )
    }

    private static func day(_ raw: String, path: String) throws -> Date {
        guard let date = PullRequestSearchDates.date(fromDay: raw) else {
            throw unreadable(path: path)
        }
        return date
    }

    private static func unreadable(path: String) -> HostToolRequestError {
        .invalidArguments(
            "\(path).cursor is not a cursor list_involved_prs returned. Pass back the next_cursor " +
                "value from a previous call, or omit cursor to start a new search."
        )
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecoded(_ raw: String) -> Data? {
        var encoded = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Base64 decoding needs the padding this encoding drops.
        let remainder = encoded.count % 4
        if remainder > 0 {
            encoded += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: encoded)
    }
}

/// `PullRequestListCursorToken`'s wire shape. Short keys because the encoded token travels in
/// every paged response, and file-private because nothing outside the token may build one.
private struct PullRequestListCursorPayload: Codable {
    let version: Int
    let filter: String
    let limit: Int
    let status: String
    let updatedAfter: String?
    let updatedBefore: String?
    let buckets: [String]
    let cursors: [String: String]

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case filter = "f"
        case limit = "l"
        case status = "s"
        case updatedAfter = "a"
        case updatedBefore = "b"
        case buckets = "bk"
        case cursors = "c"
    }
}

/// Where one bucket resumes after a page was partly emitted.
///
/// The naive answer — advance every bucket to its `endCursor` — silently drops up to a page per
/// bucket on a multi-bucket call, because the buckets are merged and only the newest `limit` rows
/// of that merge are emitted. Advancing past the *emitted prefix* instead re-offers everything
/// that did not fit. The cost is a bucket whose rows are never newest re-fetching the same page
/// until its siblings drain: bounded waste, correct results.
enum PullRequestListCursorAdvance {
    enum Outcome: Equatable {
        /// No pages left; the bucket drops out of the next token and is not searched again.
        case exhausted
        case resume(cursor: String)
        /// Nothing on this page was consumed and there is no earlier position to hold, so the next
        /// call fetches this same first page again.
        case restart
    }

    /// `isConsumed` answers whether a row is finished with — emitted in this response, or rejected
    /// by the filter, which no later page can change.
    static func outcome(
        pageInfo: PullRequestListPageInfo,
        summaries: [PullRequestSummary],
        incoming: String?,
        isConsumed: (PullRequestSummary) -> Bool
    ) -> Outcome {
        let consumed = summaries.prefix(while: isConsumed).count
        guard consumed < summaries.count else {
            // The whole page went out, so the page boundary is the next position. An empty page
            // lands here too, which is how a drained bucket reports itself.
            guard pageInfo.hasNextPage, let endCursor = pageInfo.endCursor, !endCursor.isEmpty else {
                return .exhausted
            }
            return .resume(cursor: endCursor)
        }
        if consumed > 0, consumed <= pageInfo.rowCursors.count {
            let cursor = pageInfo.rowCursors[consumed - 1]
            if !cursor.isEmpty {
                return .resume(cursor: cursor)
            }
        }
        // Nothing usable to advance to: hold the position this page was fetched from so its rows
        // are offered again rather than skipped.
        guard let incoming else {
            return .restart
        }
        return .resume(cursor: incoming)
    }
}
