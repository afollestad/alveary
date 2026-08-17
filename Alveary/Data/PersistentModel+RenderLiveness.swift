import Foundation
import SwiftData

extension PersistentModel {
    /// Whether a render pass may still read this instance's persisted properties.
    ///
    /// `@Query` results are not re-fetched per body evaluation: a delete that commits in the same
    /// runloop tick — through this context or merged in from another — leaves the dead instance in
    /// the published array until the query republishes, and a body re-run triggered by any *other*
    /// observation gets there first. Reading a persisted property on such a row traps inside
    /// SwiftData with `_assertionFailure`; that walk was the 0.2.2 (11) notification-click crash
    /// (`SidebarView.makeRenderContext()` → `unpinnableTaskIDs(in:)`).
    ///
    /// A committed delete leaves the instance with no `modelContext`
    /// (`DeletedModelRenderSafetyTests` locks that in); a pending one is in `isDeleted`. Both
    /// checks are in-memory state — no store round-trip — so filtering a whole query array per
    /// pass is cheap. Within one main-actor body pass nothing can invalidate a row after the
    /// filter, so gating once at pass start covers every read the pass makes.
    var isLiveForRender: Bool {
        modelContext != nil && !isDeleted
    }
}
