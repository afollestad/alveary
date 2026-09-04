import Foundation

/// A Git snapshot is shared by tool paging, proposal anchors, and the pane's bounded adapter.
/// Base/head IDs key the cache; the mutable PR number alone cannot identify reviewed code.
extension GitHubPullRequestsService {
    struct DiffComparison: Decodable, Equatable, Sendable {
        let base: String
        let head: String
    }

    func fetchDiffSnapshot(_ id: PullRequestIdentifier) async throws -> PullRequestDiffSnapshot {
        let comparison = try await diffComparison(id)
        let key = "\(id.nameWithOwner):\(comparison.base):\(comparison.head)"
        let ticket = await diffSnapshots.start(key: key) {
            do {
                let text = try await self.fetchRawDiff(id)
                guard try await self.diffComparison(id) == comparison else { throw PullRequestDiffError.revisionChanged }
                return try await Task.detached {
                    try PullRequestDiffSnapshot.make(text: text, baseOID: comparison.base, headOID: comparison.head)
                }.value
            } catch where Self.needsGitDiff(error) {
                let githubCLI = try await self.resolveGitHubCLI()
                return try await GitHubPullRequestGitDiff(shell: self.diffShellRunner, githubCLI: githubCLI)
                    .prepare(id: id, comparison: comparison)
            }
        }
        guard let snapshot = try await diffSnapshots.value(id: ticket) else { throw PullRequestDiffError.expired }
        return snapshot
    }

    static func needsGitDiff(_ error: Error) -> Bool {
        guard let error = error as? PullRequestsServiceError else { return false }
        return error == .requestFailed(statusCode: 406) || error == .responseTooLarge
    }

    func diffComparison(_ id: PullRequestIdentifier) async throws -> DiffComparison {
        let githubCLI = try await resolveGitHubCLI()
        let result = try await runGitHubCLIRetryingTransientFailures(
            executable: githubCLI,
            args: ["api", "repos/\(id.nameWithOwner)/pulls/\(id.number)", "--jq", "{base: .base.sha, head: .head.sha}"],
            timeout: .seconds(20), stdoutLimitBytes: 4_096, retryBudget: .seconds(25)
        )
        guard result.succeeded else { throw Self.makeError(from: result) }
        guard !result.stdoutWasTruncated else { throw PullRequestsServiceError.responseTooLarge }
        guard let comparison = try? JSONDecoder().decode(DiffComparison.self, from: result.stdoutData),
              Self.isObjectID(comparison.base), Self.isObjectID(comparison.head) else {
            throw PullRequestDiffError.invalidComparison
        }
        return comparison
    }

    private static func isObjectID(_ value: String) -> Bool {
        (value.count == 40 || value.count == 64) && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0)
        }
    }
}
