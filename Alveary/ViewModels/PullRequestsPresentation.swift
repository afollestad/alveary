import Foundation

enum PullRequestsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case reviewing = "Reviewing"
    case authored = "Authored"

    var id: String { rawValue }
}

extension PullRequestStatus {
    /// Menu ordering for the status filter.
    static let filterCases: [PullRequestStatus] = [.open, .draft, .merged, .closed]

    var filterLabel: String {
        switch self {
        case .open:
            return "Open"
        case .draft:
            return "Draft"
        case .merged:
            return "Merged"
        case .closed:
            return "Closed"
        }
    }
}

struct PullRequestListSection: Identifiable, Equatable {
    let id: String
    /// `nil` renders the rows without a heading.
    let title: String?
    let rows: [PullRequestSummary]
}

/// Compact single-unit relative age: "now", "5m", "3h", "2d", "3w", "1mo", "2y".
func compactRelativeAge(from date: Date, relativeTo now: Date) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    let minute = 60.0
    let hour = 60 * minute
    let day = 24 * hour
    let week = 7 * day
    let month = 30 * day
    let year = 365 * day

    if seconds < minute {
        return "now"
    }
    if seconds < hour {
        return "\(Int(seconds / minute))m"
    }
    if seconds < day {
        return "\(Int(seconds / hour))h"
    }
    if seconds < week {
        return "\(Int(seconds / day))d"
    }
    if seconds < month {
        return "\(Int(seconds / week))w"
    }
    if seconds < year {
        return "\(Int(seconds / month))mo"
    }
    return "\(Int(seconds / year))y"
}
