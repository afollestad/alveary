import Foundation

// Paging and date-bound inputs for `PullRequestsService.listInvolvedPullRequests`, split from
// `PullRequestsService.swift` to keep that file under the length limit.

/// The one rendering of a `updated:` search bound. Day granularity in UTC is the contract the
/// host tool's `updated_after` / `updated_before` inputs advertise, so the qualifier and the
/// schema cannot drift apart.
///
/// The formatter is built per call rather than cached: a search query is assembled once per fetch,
/// and a `static let DateFormatter` would need main-actor isolation this actor-owned caller cannot
/// reach. `PullRequestHostToolDates.canonical` makes the same trade.
enum PullRequestSearchDates {
    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Reads one of the tool's `YYYY-MM-DD` inputs back, or nil if it is not exactly that.
    ///
    /// The round trip is the check: even non-lenient, `DateFormatter` accepts `2026-1-1` and rolls
    /// `2026-02-31` forward into March, so a plain parse would search a window the caller never
    /// named and report it back as theirs.
    static func date(fromDay day: String) -> Date? {
        guard let date = dayFormatter.date(from: day), dayFormatter.string(from: date) == day else {
            return nil
        }
        return date
    }

    private static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}

/// What one list fetch asks for beyond its buckets. Every default reproduces the single
/// unpaginated page the screen and the host tool have always fetched, so `firstPage` cannot change
/// behavior — which is what lets pagination land without touching either caller's first request.
struct PullRequestListOptions: Equatable, Sendable {
    /// Rows fetched per bucket. Clamped into GitHub's `search` page bounds where it reaches the
    /// query, so a caller cannot put an out-of-range `first:` on the wire.
    var pageSize: Int
    /// Where each bucket resumes. A bucket absent from this map starts at its first page; the
    /// tokens are GitHub's own opaque `edges.cursor` / `pageInfo.endCursor` strings.
    var cursors: [PullRequestInvolvementBucket: String]
    /// `updated:` bounds applied to every requested bucket, at day granularity in UTC.
    var updatedAfter: Date?
    var updatedBefore: Date?

    init(
        pageSize: Int = PullRequestListOptions.defaultPageSize,
        cursors: [PullRequestInvolvementBucket: String] = [:],
        updatedAfter: Date? = nil,
        updatedBefore: Date? = nil
    ) {
        self.pageSize = pageSize
        self.cursors = cursors
        self.updatedAfter = updatedAfter
        self.updatedBefore = updatedBefore
    }

    /// What every caller fetched before pagination existed.
    static let defaultPageSize = 50
    /// GitHub's `search` connection ceiling.
    static let maxPageSize = 100
    static let firstPage = PullRequestListOptions()

    var resolvedPageSize: Int {
        min(max(pageSize, 1), Self.maxPageSize)
    }
}

/// Where one bucket's page ended.
///
/// `rowCursors` aligns index-for-index with that bucket's summaries, which is what lets a caller
/// that emitted only a *prefix* of them resume from the row it stopped at rather than from the
/// page boundary — advancing to `endCursor` would drop everything it did not emit.
struct PullRequestListPageInfo: Equatable, Sendable {
    let endCursor: String?
    let hasNextPage: Bool
    let rowCursors: [String]

    /// Loaded, with nothing more to fetch. Also what a SAML-forbidden bucket reads as: it decodes
    /// as null, and a caller must not page it forever.
    static let exhausted = PullRequestListPageInfo(endCursor: nil, hasNextPage: false, rowCursors: [])
}
