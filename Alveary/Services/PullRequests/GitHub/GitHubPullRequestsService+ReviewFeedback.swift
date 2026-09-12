import Foundation

extension GitHubPullRequestsService {
    /// Separate from the bounded detail query: a review must see replies beyond the UI's first page.
    func fetchReviewFeedback(_ id: PullRequestIdentifier) async throws -> Data {
        let executable = try await resolveGitHubCLI()
        var payload: [String: Any] = [:]
        var acquiredBytes = 0
        for kind in FeedbackConnection.allCases {
            var nodes = try await feedbackPages(id: id, kind: kind, executable: executable, acquiredBytes: &acquiredBytes)
            if kind == .reviewThreads {
                for index in nodes.indices {
                    guard let threadID = nodes[index]["id"] as? String,
                          let connection = nodes[index]["comments"] as? [String: Any] else {
                        throw PullRequestsServiceError.decodingFailed("Missing review thread comments")
                    }
                    nodes[index]["comments"] = try await threadCommentPages(
                        threadID: threadID, firstPage: connection, executable: executable, acquiredBytes: &acquiredBytes
                    )
                }
            }
            payload[kind.rawValue] = nodes
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

private extension GitHubPullRequestsService {
    enum FeedbackConnection: String, CaseIterable {
        case comments, reviews, reviewThreads

        var selection: String {
            switch self {
            case .comments: "id body author { login } createdAt"
            case .reviews: "id body author { login } state submittedAt"
            case .reviewThreads:
                """
                id path line diffSide isResolved isOutdated
                comments(first:100) {
                  pageInfo { hasNextPage endCursor }
                  nodes { id body author { login } createdAt state diffHunk }
                }
                """
            }
        }
    }

    func feedbackPages(
        id: PullRequestIdentifier, kind: FeedbackConnection, executable: String, acquiredBytes: inout Int
    ) async throws -> [[String: Any]] {
        let query = """
        query($owner:String!, $repo:String!, $number:Int!, $cursor:String) {
          repository(owner:$owner, name:$repo) { pullRequest(number:$number) {
            \(kind.rawValue)(first:100, after:$cursor) {
              pageInfo { hasNextPage endCursor }
              nodes { \(kind.selection) }
            }
          } }
        }
        """
        var result: [[String: Any]] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            var args = ["api", "graphql", "-f", "query=\(query)", "-f", "owner=\(id.owner)",
                        "-f", "repo=\(id.repo)", "-F", "number=\(id.number)"]
            if let cursor { args += ["-f", "cursor=\(cursor)"] }
            let data = try await feedbackPage(args: args, executable: executable, acquiredBytes: &acquiredBytes)
            guard let repository = data["repository"] as? [String: Any],
                  let pullRequest = repository["pullRequest"] as? [String: Any],
                  let page = pullRequest[kind.rawValue] as? [String: Any],
                  let nodes = page["nodes"] as? [[String: Any]] else {
                throw PullRequestsServiceError.decodingFailed("Incomplete review feedback")
            }
            result += nodes.filter { ($0["state"] as? String) != "PENDING" }
            cursor = try nextFeedbackCursor(page, seen: &seen)
            guard result.count <= 100_000 else { throw PullRequestsServiceError.responseTooLarge }
        } while cursor != nil
        return result
    }

    func threadCommentPages(
        threadID: String, firstPage: [String: Any], executable: String, acquiredBytes: inout Int
    ) async throws -> [[String: Any]] {
        guard var result = firstPage["nodes"] as? [[String: Any]] else {
            throw PullRequestsServiceError.decodingFailed("Incomplete thread replies")
        }
        var seen = Set<String>()
        var cursor = try nextFeedbackCursor(firstPage, seen: &seen)
        let query = """
        query($id:ID!, $cursor:String!) { node(id:$id) { ... on PullRequestReviewThread {
          comments(first:100, after:$cursor) {
            pageInfo { hasNextPage endCursor }
            nodes { id body author { login } createdAt state diffHunk }
          }
        } } }
        """
        while let current = cursor {
            let data = try await feedbackPage(
                args: ["api", "graphql", "-f", "query=\(query)", "-f", "id=\(threadID)", "-f", "cursor=\(current)"],
                executable: executable, acquiredBytes: &acquiredBytes
            )
            guard let node = data["node"] as? [String: Any], let page = node["comments"] as? [String: Any],
                  let nodes = page["nodes"] as? [[String: Any]] else {
                throw PullRequestsServiceError.decodingFailed("Incomplete thread replies")
            }
            result += nodes
            cursor = try nextFeedbackCursor(page, seen: &seen)
            guard result.count <= 100_000 else { throw PullRequestsServiceError.responseTooLarge }
        }
        return result.filter { ($0["state"] as? String) != "PENDING" }
    }

    func feedbackPage(args: [String], executable: String, acquiredBytes: inout Int) async throws -> [String: Any] {
        try Task.checkCancellation()
        let response = try await runGitHubCLIRetryingTransientFailures(
            executable: executable, args: args, timeout: .seconds(20), stdoutLimitBytes: 8 * 1024 * 1024
        )
        guard response.succeeded else { throw Self.makeError(from: response) }
        acquiredBytes += response.stdoutData.count
        guard !response.stdoutWasTruncated, acquiredBytes <= 64 * 1024 * 1024 else {
            throw PullRequestsServiceError.responseTooLarge
        }
        guard let root = try JSONSerialization.jsonObject(with: response.stdoutData) as? [String: Any],
              (root["errors"] as? [Any] ?? []).isEmpty, let data = root["data"] as? [String: Any] else {
            throw PullRequestsServiceError.decodingFailed("GitHub did not return complete review feedback")
        }
        return data
    }

    func nextFeedbackCursor(_ page: [String: Any], seen: inout Set<String>) throws -> String? {
        guard let info = page["pageInfo"] as? [String: Any], let hasNext = info["hasNextPage"] as? Bool else {
            throw PullRequestsServiceError.decodingFailed("Missing feedback pagination state")
        }
        guard hasNext else { return nil }
        guard let cursor = info["endCursor"] as? String, !cursor.isEmpty, seen.insert(cursor).inserted else {
            throw PullRequestsServiceError.decodingFailed("Review feedback pagination did not advance")
        }
        return cursor
    }
}
