import Foundation

extension GitHubPullRequestsService {
    func fetchReviewContext(_ id: PullRequestIdentifier) async throws -> PullRequestReviewContext {
        let data = try await reviewMetadata(id, context: true)
        return PullRequestReviewContext(detail: Self.makeDetail(id: id, node: data.node, viewer: data.viewer))
    }

    func fetchRevision(_ id: PullRequestIdentifier) async throws -> PullRequestRevision {
        let data = try await reviewMetadata(id, context: false)
        return PullRequestRevision(status: Self.makeStatus(state: data.node.state ?? "", isDraft: data.node.isDraft ?? false),
                                   baseRefOid: data.node.baseRefOid, headRefOid: data.node.headRefOid)
    }

    private func reviewMetadata(
        _ id: PullRequestIdentifier, context: Bool
    ) async throws -> (node: PullRequestDetailNode, viewer: GraphQLActorNode?) {
        let fields = context ? "title url body changedFiles author { login }" : ""
        let query = """
        query($owner:String!, $name:String!, $number:Int!) {
          rateLimit { cost }
          \(context ? "viewer { login }" : "")
          repository(owner:$owner, name:$name) { pullRequest(number:$number) {
            state isDraft baseRefOid headRefOid \(fields)
          } }
        }
        """
        let result = try await runGitHubCLIRetryingTransientFailures(
            executable: resolveGitHubCLI(),
            args: ["api", "graphql", "-f", "query=\(query)", "-f", "owner=\(id.owner)",
                   "-f", "name=\(id.repo)", "-F", "number=\(id.number)"],
            timeout: .seconds(20), stdoutLimitBytes: 8 * 1024 * 1024, retryBudget: .seconds(25),
            shareRead: context
        )
        let decoded = try decodeGraphQL(DetailGraphQLData.self, from: result)
        guard let node = decoded.data.repository?.pullRequest, node.state != nil else {
            throw PullRequestsServiceError.decodingFailed("Missing pull request revision")
        }
        return (node, decoded.data.viewer)
    }
}
