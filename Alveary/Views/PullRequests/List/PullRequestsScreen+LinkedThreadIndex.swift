import SwiftData

/// Screen-lifetime memoization of local thread links, without publishing state while the screen renders.
/// Only changed JSON is decoded; rows receive one shared set instead of scanning owners individually.
@MainActor
final class PullRequestLinkedThreadIndex {
    private let decode: (String?) -> [LinkedPullRequest]
    private var entries: [PersistentIdentifier: PullRequestLinkedThreadIndexEntry] = [:]
    private var linkedIdentifiers: Set<PullRequestIdentifier> = []

    init(decode: @escaping (String?) -> [LinkedPullRequest] = LinkedPullRequestStorage.decode) {
        self.decode = decode
    }

    /// Read every live row's eligibility and payload before a cache hit so SwiftUI keeps observing
    /// those fields on warm passes. Query results can briefly retain archived or deleted rows.
    func identifiers(in threads: [AgentThread]) -> Set<PullRequestIdentifier> {
        var liveIDs: Set<PersistentIdentifier> = []
        var membershipChanged = false
        for thread in threads where thread.isLiveForRender {
            let archivedAt = thread.archivedAt
            let isDraft = thread.isDraft
            let json = thread.linkedPullRequestsJSON
            guard archivedAt == nil, !isDraft, let json else {
                continue
            }
            let id = thread.persistentModelID
            liveIDs.insert(id)
            let previous = entries[id]
            guard previous?.json != json else {
                continue
            }
            let identifiers = Set(decode(json).map(\.id))
            if identifiers != (previous?.identifiers ?? []) {
                membershipChanged = true
            }
            entries[id] = PullRequestLinkedThreadIndexEntry(json: json, identifiers: identifiers)
        }

        let removedIDs = entries.keys.filter { !liveIDs.contains($0) }
        for id in removedIDs {
            if let removed = entries.removeValue(forKey: id), !removed.identifiers.isEmpty {
                membershipChanged = true
            }
        }
        if membershipChanged {
            var identifiers: Set<PullRequestIdentifier> = []
            for entry in entries.values {
                identifiers.formUnion(entry.identifiers)
            }
            // Retain the shared buffer when a duplicate owner or refreshed summary changed no badges.
            if identifiers != linkedIdentifiers {
                linkedIdentifiers = identifiers
            }
        }
        return linkedIdentifiers
    }
}

private struct PullRequestLinkedThreadIndexEntry {
    let json: String
    let identifiers: Set<PullRequestIdentifier>
}
