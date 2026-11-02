import Foundation

/// One pull request the user ignored. `lastSeenAt` is the last time the sync saw it open and
/// unsubscribed; an entry GitHub stops returning is dropped once that ages past the retention.
struct IgnoredPullRequestEntry: Codable, Sendable, Equatable {
    let id: PullRequestIdentifier
    let ignoredAt: Date
    var lastSeenAt: Date
}

struct IgnoredPullRequestsSnapshot: Codable, Sendable, Equatable {
    var entries: [IgnoredPullRequestEntry]
    var lastReconciledAt: Date?

    static let empty = IgnoredPullRequestsSnapshot(entries: [], lastReconciledAt: nil)
}

/// Persists the ignore list as JSON under app support. A missing or unreadable file loads as an
/// empty list rather than an error: the worst outcome is ignored rows reappearing, which the
/// user can undo, while an error would leave the screen unable to load at all.
actor IgnoredPullRequestsStore {
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

    func load() -> IgnoredPullRequestsSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(IgnoredPullRequestsSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    func save(_ snapshot: IgnoredPullRequestsSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}
