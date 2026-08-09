#if DEBUG
import Foundation

/// One canned Git working directory: everything `DemoGitService` needs to answer for a path
/// without shelling out. Keeping it a value type keeps the decorator `Sendable` with only `let`
/// state, which the toolbar's `Task.detached` stats read requires.
struct DemoGitWorkspace: Sendable {
    let path: String
    let branch: String
    let statuses: [FileStatus]
    /// Must equal the parsed sum of `diffsByPath` — the toolbar badge and the pane's file rows
    /// render side by side, so a drift shows as one screenshot contradicting itself.
    /// `DemoGitWorkspaceTests` asserts it.
    let stats: DiffStats
    let hasUnpushedCommits: Bool
    let commits: [CommitInfo]
    /// Unified diff text per changed path, plus `combinedDiff` for a whole-scope request.
    let diffsByPath: [String: String]
    let combinedDiff: String
}

enum DemoGitWorkspaces {
    static func workspace(for directory: String) -> DemoGitWorkspace? {
        let normalized = CanonicalPath.normalize(directory)
        return all.first { CanonicalPath.normalize($0.path) == normalized }
    }

    /// Paths demo mode owns. Anything else falls through to the real Git service, so a demo build
    /// still behaves normally against a project the developer added by hand.
    static let ownedPathPrefix = "/Users/demo/"

    static let all: [DemoGitWorkspace] = [tripSharing, waypoint, ledger, hummingbird]

    /// The flagship worktree behind "Add trip sharing" — the one screenshots open the pane on.
    static let tripSharing = DemoGitWorkspace(
        path: DemoData.tripSharingWorktreePath,
        branch: DemoData.tripSharingBranch,
        statuses: [
            FileStatus(path: "Sources/Waypoint/Sharing/TripShareLink.swift", originalPath: nil, status: .added, isStaged: true),
            FileStatus(path: "Sources/Waypoint/Sharing/ShareSheet.swift", originalPath: nil, status: .modified, isStaged: true),
            FileStatus(path: "Sources/Waypoint/Trips/TripStore.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "Tests/WaypointTests/TripShareLinkTests.swift", originalPath: nil, status: .untracked, isStaged: false),
            FileStatus(path: "Docs/sharing.md", originalPath: "Docs/share.md", status: .renamed, isStaged: false)
        ],
        stats: DiffStats(additions: 34, deletions: 4),
        hasUnpushedCommits: true,
        commits: [
            CommitInfo(
                hash: "9f2c1d4a7b8e35906c1af2d8be47301fa5c9e6b2",
                message: "Mint signed share links for a trip",
                author: "Rowan Fields",
                date: DemoData.hoursAgo(3)
            ),
            CommitInfo(
                hash: "2b70e5c98d13af460b25c7e0193fd8a641c7b0de",
                message: "Add a share sheet to the trip detail screen",
                author: "Rowan Fields",
                date: DemoData.hoursAgo(6)
            ),
            CommitInfo(
                hash: "c418ad0e6f92b71350da8c4e27f0916bd35a7e84",
                message: "Move sharing docs alongside the feature",
                author: "Rowan Fields",
                date: DemoData.daysAgo(1)
            )
        ],
        diffsByPath: [
            "Sources/Waypoint/Sharing/TripShareLink.swift": shareLinkDiff,
            "Sources/Waypoint/Sharing/ShareSheet.swift": shareSheetDiff,
            "Sources/Waypoint/Trips/TripStore.swift": tripStoreDiff,
            "Tests/WaypointTests/TripShareLinkTests.swift": shareLinkTestsDiff,
            "Docs/sharing.md": sharingDocsDiff
        ],
        // `shareLinkTestsDiff` is deliberately absent: the file is untracked, and a real
        // `git diff` omits untracked files — the pane fetches those through `syntheticAddedDiff`.
        combinedDiff: [shareLinkDiff, shareSheetDiff, tripStoreDiff, sharingDocsDiff].joined(separator: "\n")
    )

    static let waypoint = DemoGitWorkspace(
        path: DemoData.waypointPath,
        branch: "main",
        statuses: [
            FileStatus(path: "Sources/Waypoint/Map/TileCache.swift", originalPath: nil, status: .modified, isStaged: false)
        ],
        stats: DiffStats(additions: 19, deletions: 6),
        hasUnpushedCommits: false,
        commits: [],
        diffsByPath: ["Sources/Waypoint/Map/TileCache.swift": DemoPullRequestFixtures.tileCacheDiff],
        combinedDiff: DemoPullRequestFixtures.tileCacheDiff
    )

    static let ledger = DemoGitWorkspace(
        path: DemoData.ledgerPath,
        branch: "main",
        statuses: [
            FileStatus(path: "Sources/Ledger/Logging/EventLogger.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "Sources/Ledger/Logging/LogField.swift", originalPath: nil, status: .added, isStaged: true)
        ],
        stats: DiffStats(additions: 13, deletions: 3),
        hasUnpushedCommits: false,
        commits: [],
        diffsByPath: [
            "Sources/Ledger/Logging/EventLogger.swift": eventLoggerDiff,
            "Sources/Ledger/Logging/LogField.swift": logFieldDiff
        ],
        // Unlike tripSharing's untracked test file, `LogField.swift` is a staged add, and a real
        // `git diff` includes those — so the combined scope carries it.
        combinedDiff: [eventLoggerDiff, logFieldDiff].joined(separator: "\n")
    )

    static let hummingbird = DemoGitWorkspace(
        path: DemoData.hummingbirdPath,
        branch: "main",
        statuses: [
            FileStatus(path: "Sources/Hummingbird/Search/EmptyStateView.swift", originalPath: nil, status: .modified, isStaged: false)
        ],
        stats: DiffStats(additions: 4, deletions: 1),
        hasUnpushedCommits: false,
        commits: [],
        diffsByPath: ["Sources/Hummingbird/Search/EmptyStateView.swift": emptyStateDiff],
        combinedDiff: emptyStateDiff
    )
}

// Hunk bodies deliberately carry no blank lines; see the note atop
// `DemoPullRequestFixtures+Diffs.swift` for why.
private extension DemoGitWorkspaces {
    static let shareLinkDiff = """
        diff --git a/Sources/Waypoint/Sharing/TripShareLink.swift b/Sources/Waypoint/Sharing/TripShareLink.swift
        new file mode 100644
        index 0000000..4c81f30
        --- /dev/null
        +++ b/Sources/Waypoint/Sharing/TripShareLink.swift
        @@ -0,0 +1,12 @@
        +import Foundation
        +/// A signed, expiring link to one trip's read-only itinerary.
        +struct TripShareLink: Hashable, Sendable {
        +    let tripID: Trip.ID
        +    let token: String
        +    let expiresAt: Date
        +    var url: URL? {
        +        var components = URLComponents(string: "https://waypoint.app/t/\\(tripID)")
        +        components?.queryItems = [URLQueryItem(name: "k", value: token)]
        +        return components?.url
        +    }
        +}
        """

    static let shareSheetDiff = """
        diff --git a/Sources/Waypoint/Sharing/ShareSheet.swift b/Sources/Waypoint/Sharing/ShareSheet.swift
        index 8ad1c07..e2f9b45 100644
        --- a/Sources/Waypoint/Sharing/ShareSheet.swift
        +++ b/Sources/Waypoint/Sharing/ShareSheet.swift
        @@ -12,5 +12,12 @@ struct ShareSheet: View {
             let trip: Trip
        -    var body: some View {
        -        ShareLink(item: trip.title)
        -    }
        +    @State private var link: TripShareLink?
        +    var body: some View {
        +        Group {
        +            if let url = link?.url {
        +                ShareLink(item: url) { Label("Share trip", systemImage: "square.and.arrow.up") }
        +            } else {
        +                ProgressView().task { link = try? await sharing.mintLink(for: trip) }
        +            }
        +        }
        +    }
         }
        """

    static let tripStoreDiff = """
        diff --git a/Sources/Waypoint/Trips/TripStore.swift b/Sources/Waypoint/Trips/TripStore.swift
        index 5c31e88..a90de17 100644
        --- a/Sources/Waypoint/Trips/TripStore.swift
        +++ b/Sources/Waypoint/Trips/TripStore.swift
        @@ -64,4 +64,7 @@ actor TripStore {
             func trip(id: Trip.ID) throws -> Trip {
                 try context.fetchOne(Trip.self, id: id)
             }
        +    func sharedTrip(token: String) throws -> Trip {
        +        try context.fetchOne(Trip.self, matching: .shareToken(token))
        +    }
         }
        """

    static let shareLinkTestsDiff = """
        diff --git a/Tests/WaypointTests/TripShareLinkTests.swift b/Tests/WaypointTests/TripShareLinkTests.swift
        new file mode 100644
        index 0000000..1d4e7ba
        --- /dev/null
        +++ b/Tests/WaypointTests/TripShareLinkTests.swift
        @@ -0,0 +1,7 @@
        +import Testing
        +@testable import Waypoint
        +@Test func shareLinkCarriesItsToken() throws {
        +    let link = TripShareLink(tripID: .preview, token: "abc123", expiresAt: .distantFuture)
        +    let url = try #require(link.url)
        +    #expect(url.absoluteString.contains("k=abc123"))
        +}
        """

    static let sharingDocsDiff = """
        diff --git a/Docs/share.md b/Docs/sharing.md
        similarity index 74%
        rename from Docs/share.md
        rename to Docs/sharing.md
        index 71b0c8e..9de4a12 100644
        --- a/Docs/share.md
        +++ b/Docs/sharing.md
        @@ -1,3 +1,4 @@
         # Sharing a trip
        -Sharing is not implemented yet.
        +A share link is signed and expires after seven days.
        +Anyone holding the link sees a read-only itinerary.
         Revoking a link invalidates it immediately.
        """

    static let eventLoggerDiff = """
        diff --git a/Sources/Ledger/Logging/EventLogger.swift b/Sources/Ledger/Logging/EventLogger.swift
        index 2f7a913..b0c4e58 100644
        --- a/Sources/Ledger/Logging/EventLogger.swift
        +++ b/Sources/Ledger/Logging/EventLogger.swift
        @@ -8,5 +8,7 @@ struct EventLogger: Sendable {
             let subsystem: String
        -    func log(_ message: String) {
        -        print("[\\(subsystem)] \\(message)")
        -    }
        +    func log(_ event: StaticString, _ fields: LogField...) {
        +        var line = LogLine(subsystem: subsystem, event: event)
        +        fields.forEach { line.append($0) }
        +        transport.write(line.encoded())
        +    }
         }
        """

    static let logFieldDiff = """
        diff --git a/Sources/Ledger/Logging/LogField.swift b/Sources/Ledger/Logging/LogField.swift
        new file mode 100644
        index 0000000..8c2f1d7
        --- /dev/null
        +++ b/Sources/Ledger/Logging/LogField.swift
        @@ -0,0 +1,8 @@
        +/// One typed key-value pair attached to a structured log line.
        +struct LogField: Sendable {
        +    let key: String
        +    let value: String
        +    static func string(_ key: String, _ value: String) -> LogField {
        +        LogField(key: key, value: value)
        +    }
        +}
        """

    static let emptyStateDiff = """
        diff --git a/Sources/Hummingbird/Search/EmptyStateView.swift b/Sources/Hummingbird/Search/EmptyStateView.swift
        index 9c0be21..40af7d3 100644
        --- a/Sources/Hummingbird/Search/EmptyStateView.swift
        +++ b/Sources/Hummingbird/Search/EmptyStateView.swift
        @@ -21,6 +21,9 @@ struct EmptyStateView: View {
                     Text(title)
                         .font(.headline)
        -            Text("Nothing here")
        +            Text(subtitle)
        +                .font(.subheadline)
        +                .foregroundStyle(.secondary)
        +                .multilineTextAlignment(.center)
                 }
             }
         }
        """
}
#endif
