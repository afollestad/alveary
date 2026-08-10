import Foundation

/// Persists the last fetched pull-request list so the screen paints instantly on
/// the next launch while the network refresh runs behind it. Load failures are
/// treated as a cold cache — never as errors, which is also what retires the flat
/// pre-bucket file shape: it simply fails to decode.
actor PullRequestsListCache {
    /// Bucket keys are the raw involvement names rather than the enum itself, so the file stays a
    /// plain JSON object — `JSONEncoder` writes a non-`String` dictionary key as a flat array.
    private struct CachedList: Codable {
        let filter: PullRequestStatusFilter
        let buckets: [String: [PullRequestSummary]]
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

    /// The buckets the last fetch produced, or nil when there is nothing usable to paint.
    ///
    /// A cache written under one status filter must not paint under another — the stored buckets
    /// were narrowed by it — so a mismatch reads as a cold cache rather than as stale rows the
    /// refresh would silently correct.
    func load(filter: PullRequestStatusFilter) -> [PullRequestInvolvementBucket: [PullRequestSummary]]? {
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? decoder.decode(CachedList.self, from: data),
              cached.filter == filter else {
            return nil
        }
        let buckets = cached.buckets.reduce(into: [PullRequestInvolvementBucket: [PullRequestSummary]]()) {
            guard let bucket = PullRequestInvolvementBucket(rawValue: $1.key) else {
                return
            }
            $0[bucket] = $1.value
        }
        return buckets.values.contains(where: { !$0.isEmpty }) ? buckets : nil
    }

    /// Callers pass every bucket they hold, not just the ones a fetch refreshed, so a lazy
    /// per-tab load cannot drop another tab's cached rows.
    func save(_ buckets: [PullRequestInvolvementBucket: [PullRequestSummary]], filter: PullRequestStatusFilter) {
        let cached = CachedList(
            filter: filter,
            buckets: Dictionary(uniqueKeysWithValues: buckets.map { ($0.key.queryVariableName, $0.value) })
        )
        guard let data = try? encoder.encode(cached) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}
