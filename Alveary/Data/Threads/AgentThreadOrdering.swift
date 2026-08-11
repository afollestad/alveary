import Foundation
import SwiftData

enum AgentThreadOrdering {
    @MainActor
    static func sorted(_ threads: [AgentThread]) -> [AgentThread] {
        threads.sorted(by: compare)
    }

    @MainActor
    static func orderedIDs(_ threads: [AgentThread]) -> [PersistentIdentifier] {
        sorted(threads).map(\.persistentModelID)
    }

    @MainActor
    static func compare(_ lhs: AgentThread, _ rhs: AgentThread) -> Bool {
        switch (lhs.modifiedAt, rhs.modifiedAt) {
        case (.some(let lhsModifiedAt), .some(let rhsModifiedAt)) where lhsModifiedAt != rhsModifiedAt:
            return lhsModifiedAt > rhsModifiedAt
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return String(describing: lhs.persistentModelID) < String(describing: rhs.persistentModelID)
    }
}
