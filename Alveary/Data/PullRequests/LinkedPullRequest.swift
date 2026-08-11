import Foundation

/// A pull request the user has associated with a thread or project.
///
/// `summary` is a cache, not truth: it is captured from GitHub when the link is
/// created and refreshed when the link's pane opens, so the toolbar glyph can
/// render a status without a network round trip. `summary.id` is the pull
/// request's identity, so the link needs no separate identifier field.
struct LinkedPullRequest: Codable, Equatable, Sendable, Identifiable {
    var summary: PullRequestSummary
    var linkedAt: Date

    var id: PullRequestIdentifier { summary.id }
}

/// The shared JSON envelope behind `AgentThread.linkedPullRequestsJSON` and
/// `Project.linkedPullRequestsJSON`, so the two columns cannot drift apart.
///
/// A malformed payload decodes to an empty list rather than throwing: the
/// contents are a refetchable cache, and a bad blob must not make its owner
/// unopenable. Encoding an empty list yields `nil` so the column clears instead
/// of persisting `[]`.
enum LinkedPullRequestStorage {
    static func decode(_ json: String?) -> [LinkedPullRequest] {
        guard let json,
              let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(LinkedPullRequestsEnvelope.self, from: data) else {
            return []
        }
        return envelope.links
    }

    static func encode(_ links: [LinkedPullRequest]) -> String? {
        guard !links.isEmpty else {
            return nil
        }
        let envelope = LinkedPullRequestsEnvelope(
            version: LinkedPullRequestsEnvelope.currentVersion,
            links: links
        )
        return (try? JSONEncoder().encode(envelope))
            .flatMap { String(data: $0, encoding: .utf8) }
    }
}

private struct LinkedPullRequestsEnvelope: Codable {
    static let currentVersion = 1

    let version: Int
    let links: [LinkedPullRequest]
}
