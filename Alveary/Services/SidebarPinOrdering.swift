import Foundation
import SwiftData

/// Appends a thread to the sidebar's pinned order without saving or renumbering.
///
/// `SidebarViewModel` owns pinning as a user action, but a schedule that targets an unpinned
/// thread has to pin it inside the same save as the definition, which cannot route through a
/// view model that normalizes and persists sidebar ordering on its own.
enum SidebarPinOrdering {
    /// One past the highest assigned pinned order. Sidebar normalization renumbers pinned items
    /// densely and clears everyone else's order, so this equals the pinned count there; taking
    /// the maximum instead keeps the append collision-free when normalization has not run.
    static func nextPinnedSortOrder(in modelContext: ModelContext) throws -> Int {
        let projectOrders = try modelContext.fetch(FetchDescriptor<Project>()).compactMap(\.pinnedSortOrder)
        let threadOrders = try modelContext.fetch(FetchDescriptor<AgentThread>()).compactMap(\.pinnedSortOrder)
        guard let highestOrder = (projectOrders + threadOrders).max() else {
            return 0
        }
        return highestOrder + 1
    }

    /// Pins `thread` at the end of the pinned order, reporting whether anything changed.
    @discardableResult
    static func pin(_ thread: AgentThread, in modelContext: ModelContext) throws -> Bool {
        guard !thread.isPinned else {
            return false
        }
        thread.isPinned = true
        thread.pinnedSortOrder = try nextPinnedSortOrder(in: modelContext)
        return true
    }
}
