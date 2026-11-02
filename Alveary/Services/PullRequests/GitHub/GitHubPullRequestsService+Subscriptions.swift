import Foundation

// The read half of notification subscriptions: one batched lookup per chunk of identifiers.
// The write, `updatePullRequestSubscription`, lives with every other mutation in `+Mutations.swift`.
extension GitHubPullRequestsService {
    /// GitHub limits how many nodes one document may name; 50 aliased lookups stays far inside
    /// that while keeping an ordinary ignore list to a single request.
    static let subscriptionLookupChunkSize = 50

    /// Chunks run one after another rather than in parallel: the usual list is one chunk, and a
    /// longer one is a background sync with nothing waiting on its latency.
    ///
    /// Results are keyed by the identifier the caller asked for, not the one GitHub returns, so a
    /// renamed or differently-cased repository still maps back to its entry.
    func fetchSubscriptionStates(
        for ids: [PullRequestIdentifier]
    ) async throws -> [PullRequestIdentifier: PullRequestSubscriptionSnapshot] {
        guard !ids.isEmpty else {
            return [:]
        }
        let ghExecutable = try await resolveGitHubCLI()
        var snapshots: [PullRequestIdentifier: PullRequestSubscriptionSnapshot] = [:]
        var start = ids.startIndex
        while start < ids.endIndex {
            let end = min(start + Self.subscriptionLookupChunkSize, ids.endIndex)
            let chunk = Array(ids[start..<end])
            let result = try await runGitHubCLIRetryingTransientFailures(
                executable: ghExecutable,
                args: Self.subscriptionLookupArgs(for: chunk),
                timeout: Self.readAttemptTimeout,
                stdoutLimitBytes: 4 * 1024 * 1024,
                retryBudget: Self.readRetryBudget,
                shareRead: false
            )
            // A deleted pull request or a SAML-protected organization nulls its alias and adds an
            // error while the rest still decode, so a partial result is the normal shape here.
            let decoded = try decodeGraphQL(SubscriptionLookupGraphQLData.self, from: result)
            for (index, id) in chunk.enumerated() {
                guard let node = decoded.data.pullRequestsByAlias["pr\(index)"],
                      let snapshot = Self.makeSubscriptionSnapshot(from: node) else {
                    continue
                }
                snapshots[id] = snapshot
            }
            start = end
        }
        return snapshots
    }

    static func makeSubscriptionSnapshot(from node: SubscriptionLookupPullRequestNode) -> PullRequestSubscriptionSnapshot? {
        guard let nodeID = node.id, let summary = makeSummary(from: node.listNode) else {
            return nil
        }
        return PullRequestSubscriptionSnapshot(
            nodeID: nodeID,
            summary: summary,
            subscription: node.viewerSubscription.flatMap(PullRequestSubscriptionState.init(rawValue:)),
            viewerCanSubscribe: node.viewerCanSubscribe ?? false
        )
    }
}

/// The lookup's `data`: one `pr<index>` alias per identifier, plus `rateLimit`, which the
/// transport reads for the usage ledger. Aliases are dynamic, so the keys are read by name.
struct SubscriptionLookupGraphQLData: Decodable {
    let pullRequestsByAlias: [String: SubscriptionLookupPullRequestNode]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AliasCodingKey.self)
        var pullRequests: [String: SubscriptionLookupPullRequestNode] = [:]
        for key in container.allKeys where key.stringValue.hasPrefix("pr") {
            // A null alias is a pull request GitHub did not return; it stays absent.
            if let pullRequest = try container.decodeIfPresent(SubscriptionLookupRepositoryNode.self, forKey: key)?.pullRequest {
                pullRequests[key.stringValue] = pullRequest
            }
        }
        pullRequestsByAlias = pullRequests
    }
}

struct SubscriptionLookupRepositoryNode: Decodable {
    let pullRequest: SubscriptionLookupPullRequestNode?
}

/// The list fragment's fields plus the subscription ones. The list half decodes through
/// `PullRequestListNode` itself, so the row mapping cannot drift from the list query's.
struct SubscriptionLookupPullRequestNode: Decodable {
    let listNode: PullRequestListNode
    let id: String?
    let viewerSubscription: String?
    let viewerCanSubscribe: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case viewerSubscription
        case viewerCanSubscribe
    }

    init(from decoder: Decoder) throws {
        listNode = try PullRequestListNode(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        viewerSubscription = try container.decodeIfPresent(String.self, forKey: .viewerSubscription)
        viewerCanSubscribe = try container.decodeIfPresent(Bool.self, forKey: .viewerCanSubscribe)
    }
}

/// `updateSubscription`'s payload.
struct UpdateSubscriptionGraphQLData: Decodable {
    let updateSubscription: UpdateSubscriptionPayloadNode?
}

struct UpdateSubscriptionPayloadNode: Decodable {
    let subscribable: SubscribableNode?
}

struct SubscribableNode: Decodable {
    let viewerSubscription: String?
}

private struct AliasCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}
