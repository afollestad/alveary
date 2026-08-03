import Foundation
import SwiftData

/// What a pin request did, so a caller can tell "nothing to do" from "cannot be done".
enum ThreadPinOutcome: Equatable {
    case changed
    /// Already in the requested state.
    case unchanged
    /// A pinned project already absorbs this thread, so an individual pin would render nowhere.
    /// Only ever returned for a pin request.
    case absorbedByPinnedProject
}

extension ThreadLifecycleService {
    /// Pins or unpins a thread and renumbers the sidebar order in the same save.
    ///
    /// The scheduled-attachment guard applies to unpinning only: an attached thread's pin is what
    /// keeps it visible while its schedule owns it.
    @discardableResult
    func setThreadPinned(threadID: PersistentIdentifier, isPinned: Bool) throws -> ThreadPinOutcome {
        guard let currentThread = modelContext.resolveThread(id: threadID),
              currentThread.archivedAt == nil,
              !currentThread.isDraft,
              currentThread.effectiveMode == .task || currentThread.project != nil else {
            throw SidebarViewModelError.threadMissing
        }
        // A pinned project absorbs its children regardless of mode, so pinning one is a no-op.
        // Checked before any flush so a refused pin touches nothing.
        if isPinned, currentThread.project?.isPinned == true {
            return .absorbedByPinnedProject
        }
        try flushPendingSidebarPinChanges()

        do {
            var didChange = try SidebarOrderNormalization.normalize(in: modelContext)
            // Re-resolve after the flush; it can save, and the row must still qualify.
            guard let dbThread = modelContext.resolveThread(id: threadID),
                  dbThread.archivedAt == nil,
                  !dbThread.isDraft,
                  dbThread.effectiveMode == .task || dbThread.project != nil else {
                throw SidebarViewModelError.threadMissing
            }
            let wasPinned = dbThread.isPinned
            if !isPinned, wasPinned {
                try requireNoScheduledTaskAttachment(dbThread)
            }
            if isPinned, !wasPinned {
                try SidebarPinOrdering.pin(dbThread, in: modelContext)
                didChange = true
            } else if !isPinned, wasPinned {
                dbThread.isPinned = false
                dbThread.pinnedSortOrder = nil
                didChange = true
            }

            didChange = try SidebarOrderNormalization.normalize(in: modelContext) || didChange
            guard didChange else {
                return .unchanged
            }
            try saveSidebarOrdering(modelContext)
            // Normalization may have renumbered unrelated rows even when this thread's own pin
            // state did not move, so `changed` means "the sidebar order changed", not "this pin
            // flipped". The caller refreshes either way.
            return .changed
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func flushPendingSidebarPinChanges() throws {
        guard modelContext.hasChanges else {
            return
        }
        try savePendingSidebarChanges(modelContext)
    }
}
