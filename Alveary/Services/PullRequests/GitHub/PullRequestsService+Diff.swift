import Foundation

extension PullRequestsService {
    /// Demo and test services already provide complete diff text; the GitHub adapter overrides
    /// this to share immutable snapshots and recover from GitHub's diff size limit.
    func fetchDiffSnapshot(_ id: PullRequestIdentifier) async throws -> PullRequestDiffSnapshot {
        let text = try await fetchDiff(id)
        return try await Task.detached { try PullRequestDiffSnapshot.make(text: text) }.value
    }

    func fetchDiffFiles(_ id: PullRequestIdentifier, paths: Set<String>) async throws -> [DiffFile] {
        let snapshot = try await fetchDiffSnapshot(id)
        return try await Task.detached { try snapshot.parsedFiles(paths: paths) }.value
    }
}
