import Foundation
import SwiftData

extension SidebarViewModel {
    func compareRegularProjects(_ lhs: Project, _ rhs: Project) -> Bool {
        compareOptionalOrder(
            lhs.sidebarSortOrder,
            rhs.sidebarSortOrder,
            fallback: { compareProjectFallback(lhs, rhs) }
        )
    }

    func comparePinnedProjects(_ lhs: Project, _ rhs: Project) -> Bool {
        compareOptionalOrder(
            lhs.pinnedSortOrder,
            rhs.pinnedSortOrder,
            fallback: { compareProjectFallback(lhs, rhs) }
        )
    }

    func compareProjectFallback(_ lhs: Project, _ rhs: Project) -> Bool {
        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.path < rhs.path
    }

    func comparePinnedThreads(_ lhs: AgentThread, _ rhs: AgentThread) -> Bool {
        compareOptionalOrder(
            lhs.pinnedSortOrder,
            rhs.pinnedSortOrder,
            fallback: {
                switch (lhs.modifiedAt, rhs.modifiedAt) {
                case (.some(let lhsActivity), .some(let rhsActivity)) where lhsActivity != rhsActivity:
                    return lhsActivity > rhsActivity
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    break
                }
                let nameComparison = lhs.displayName().localizedCaseInsensitiveCompare(rhs.displayName())
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                return String(describing: lhs.persistentModelID) < String(describing: rhs.persistentModelID)
            }
        )
    }
}

private extension SidebarViewModel {
    func compareOptionalOrder(
        _ lhsOrder: Int?,
        _ rhsOrder: Int?,
        fallback: () -> Bool
    ) -> Bool {
        switch (lhsOrder, rhsOrder) {
        case (.some(let lhs), .some(let rhs)) where lhs != rhs:
            return lhs < rhs
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return fallback()
        }
    }
}
