import Foundation

/// One immutable grouping snapshot keeps expansion, scroll aliases, and installed rows in agreement
/// even when a newer transcript arrives while this snapshot's markdown is being prepared.
@MainActor
struct AppKitTranscriptPresentation {
    let items: [ChatItem]
    let visualRows: [AppKitTranscriptVisualRow]
    let expandableRowIDs: Set<String>
    let rowIDAliases: [String: String]

    init(items: [ChatItem]) {
        self.items = items
        visualRows = AppKitTranscriptActivityGrouping.visualRows(for: items)
        expandableRowIDs = AppKitTranscriptActivityGrouping.expandableRowIDs(in: visualRows)
        rowIDAliases = AppKitTranscriptActivityGrouping.rowIDAliases(in: visualRows)
    }

    func migratedExpandedRowIDs(_ expandedRowIDs: Set<String>) -> Set<String> {
        guard !expandedRowIDs.isEmpty else { return [] }
        return AppKitTranscriptActivityGrouping.migratedExpandedRowIDs(expandedRowIDs, in: visualRows)
    }
}

/// Scoped to a transcript view, without observation, so scroll chrome can reuse grouping without
/// dirtying SwiftUI. Full item values include replacement payloads and interrupted-activity projection.
@MainActor
final class AppKitTranscriptPresentationCache {
    /// Everything `ChatTranscriptView` reads to project grouper items into transcript items.
    /// Keyed on the grouper's `itemsRevision` rather than the items themselves so a hit costs no
    /// element-wise compare; the caller must still read every observable input while building
    /// the key so SwiftUI keeps tracking them.
    struct TranscriptItemsKey: Equatable {
        /// A replacement grouper restarts its revision at zero, so identity disambiguates.
        let grouper: ObjectIdentifier
        let itemsRevision: Int
        let terminalizesInterruptedActivity: Bool
        let reviewTeamRun: ReviewTeamRun?
        let conversationID: String
    }

    struct ApprovalRequests {
        let requests: [ToolApprovalRequest]
        /// `.task(id:)` identity for loading selections; joined once here instead of per body.
        let loadID: String
    }

    private var cachedPresentation: AppKitTranscriptPresentation?
    private(set) var preparationCount = 0
    private var cachedTranscriptItemsKey: TranscriptItemsKey?
    private var cachedTranscriptItems: [ChatItem] = []
    private var cachedApprovalRequestsKey: (grouper: ObjectIdentifier, itemsRevision: Int)?
    private var cachedApprovalRequests = ApprovalRequests(requests: [], loadID: "")

    func presentation(for items: [ChatItem]) -> AppKitTranscriptPresentation {
        if let cachedPresentation, cachedPresentation.items == items {
            return cachedPresentation
        }
        let presentation = AppKitTranscriptPresentation(items: items)
        cachedPresentation = presentation
        preparationCount += 1
        return presentation
    }

    /// Returns the same array storage for the same key, so downstream `[ChatItem] ==` checks
    /// short-circuit on identity instead of comparing every item.
    func transcriptItems(for key: TranscriptItemsKey, build: () -> [ChatItem]) -> [ChatItem] {
        if cachedTranscriptItemsKey == key {
            return cachedTranscriptItems
        }
        let items = build()
        cachedTranscriptItemsKey = key
        cachedTranscriptItems = items
        return items
    }

    func approvalRequests(grouper: ChatItemGrouper, build: () -> [ToolApprovalRequest]) -> ApprovalRequests {
        let key = (grouper: ObjectIdentifier(grouper), itemsRevision: grouper.itemsRevision)
        if let cachedApprovalRequestsKey, cachedApprovalRequestsKey == key {
            return cachedApprovalRequests
        }
        let requests = build()
        cachedApprovalRequestsKey = key
        cachedApprovalRequests = ApprovalRequests(requests: requests, loadID: requests.map(\.sessionId).joined(separator: "|"))
        return cachedApprovalRequests
    }
}
