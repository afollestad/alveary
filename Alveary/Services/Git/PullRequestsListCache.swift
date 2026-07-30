import Foundation

/// Persists the last fetched pull-request list so the screen paints instantly on
/// the next launch while the network refresh runs behind it. Load failures are
/// treated as a cold cache — never as errors.
actor PullRequestsListCache {
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

    func load() -> [PullRequestSummary]? {
        guard let data = try? Data(contentsOf: fileURL),
              let summaries = try? decoder.decode([PullRequestSummary].self, from: data),
              !summaries.isEmpty else {
            return nil
        }
        return summaries
    }

    func save(_ summaries: [PullRequestSummary]) {
        guard let data = try? encoder.encode(summaries) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}
