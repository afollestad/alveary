import Foundation

extension Array where Element == TaskEntry {
    var taskListPresentationOrder: [TaskEntry] {
        enumerated()
            .sorted { lhs, rhs in
                let lhsRank = lhs.element.status.taskListSortRank
                let rhsRank = rhs.element.status.taskListSortRank
                if lhsRank == rhsRank {
                    return lhs.offset < rhs.offset
                }
                return lhsRank < rhsRank
            }
            .map(\.element)
    }
}

extension TaskEntry.Status {
    var taskListSortRank: Int {
        switch self {
        case .inProgress:
            return 0
        case .interrupted:
            return 1
        case .pending:
            return 2
        case .completed:
            return 3
        }
    }

    var taskListAccessibilityLabel: String {
        switch self {
        case .inProgress:
            return "In progress"
        case .interrupted:
            return "Interrupted"
        case .pending:
            return "Pending"
        case .completed:
            return "Completed"
        }
    }
}
