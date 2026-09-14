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
    private var cachedPresentation: AppKitTranscriptPresentation?
    private(set) var preparationCount = 0

    func presentation(for items: [ChatItem]) -> AppKitTranscriptPresentation {
        if let cachedPresentation, cachedPresentation.items == items {
            return cachedPresentation
        }
        let presentation = AppKitTranscriptPresentation(items: items)
        cachedPresentation = presentation
        preparationCount += 1
        return presentation
    }
}
