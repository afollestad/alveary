import Foundation

enum PullRequestsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case reviewing = "Reviewing"
    case authored = "Authored"

    var id: String { rawValue }

    /// The involvement buckets this tab renders, and so the only ones it fetches. Reviewing is
    /// both review buckets because it sections "Pending review" above "Previously reviewed".
    var requiredBuckets: Set<PullRequestInvolvementBucket> {
        switch self {
        case .all:
            return Set(PullRequestInvolvementBucket.allCases)
        case .reviewing:
            return [.reviewRequested, .reviewed]
        case .authored:
            return [.authored]
        }
    }
}

extension PullRequestStatusFilter {
    /// Menu ordering for the status filter; `all` leads because it is the widest choice.
    static let menuCases: [PullRequestStatusFilter] = [.all, .open, .draft, .merged, .closed]

    var filterLabel: String {
        switch self {
        case .all:
            return "All"
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

/// One row's rendered text, derived once per `(summary, showsRepository, referenceDate)` instead
/// of on every `body` pass.
///
/// `PullRequestRow` used to build all of this inline, which cost each visible row two
/// `compactRelativeAge` calls, two segment-cache probes for the same title (render plus
/// accessibility label), and a seven-part `joined` — eagerly, because `.accessibilityLabel(_:)`
/// takes a `String`. Baking `ageText` in also narrows the minute tick: `referenceDate` is no
/// longer a row input, so a tick now invalidates only the rows whose *displayed* age actually
/// changed rather than every visible row.
struct PullRequestRowModel: Identifiable, Equatable {
    let summary: PullRequestSummary
    /// Carried per row rather than passed alongside, so it lands in `==` with everything else the
    /// row draws.
    let showsRepository: Bool
    let ageText: String
    let accessibilityLabel: String

    var id: PullRequestIdentifier { summary.id }

    init(summary: PullRequestSummary, showsRepository: Bool, referenceDate: Date) {
        self.summary = summary
        self.showsRepository = showsRepository
        let age = compactRelativeAge(from: summary.updatedAt, relativeTo: referenceDate)
        ageText = age
        var parts = [
            summary.status.accessibilityName,
            AppMarkdownInlineLabel.plainText(from: summary.title, detectingFileMentions: false),
            "by \(summary.authorLogin)"
        ]
        if showsRepository {
            parts.append("in \(summary.repositoryNameWithOwner)")
        }
        parts.append("branch \(summary.headRefName)")
        parts.append("updated \(age) ago")
        parts.append("\(summary.additions) added, \(summary.deletions) deleted")
        accessibilityLabel = parts.joined(separator: ", ")
    }
}

/// One entry in the list's single lazy column — headings and rows interleaved.
///
/// The screen renders one `LazyVStack` over these rather than a `LazyVStack` per section inside a
/// non-lazy `VStack`: that outer stack had to size every section, including ones entirely below
/// the fold, so laziness never spanned the whole scroll content.
enum PullRequestListItem: Identifiable, Equatable {
    case header(id: String, title: String)
    case row(PullRequestRowModel)

    var id: String {
        switch self {
        case .header(let id, _):
            return "header:\(id)"
        case .row(let model):
            return "row:\(model.id.displayKey)"
        }
    }

    /// Flattens shaped sections into that column. A section with no title contributes rows only —
    /// the Authored tab stays flat and untitled.
    static func flatten(
        _ sections: [PullRequestListSection],
        showsRepository: Bool,
        referenceDate: Date
    ) -> [PullRequestListItem] {
        sections.flatMap { section -> [PullRequestListItem] in
            let rows = section.rows.map { summary in
                PullRequestListItem.row(
                    PullRequestRowModel(
                        summary: summary,
                        showsRepository: showsRepository,
                        referenceDate: referenceDate
                    )
                )
            }
            guard let title = section.title else {
                return rows
            }
            return [.header(id: section.id, title: title)] + rows
        }
    }
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
