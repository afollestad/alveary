import Foundation
import SwiftData

/// A selection that may own a project, reduced to identifiers so the deferred
/// persistence job never dereferences a selection token synchronously.
enum LastActiveProjectOwner: Equatable {
    case project(PersistentIdentifier)
    case thread(PersistentIdentifier)

    init?(selection: SidebarItem?) {
        switch selection {
        case .project(let project):
            self = .project(project.persistentModelID)
        case .thread(let thread):
            self = .thread(thread.persistentModelID)
        case .skills, .mcp, .scheduled, .settings, nil:
            return nil
        }
    }
}

enum LastActiveProjectResolution: Equatable {
    /// The selection carries no project ownership; leave the stored value alone.
    case unowned
    case path(String?)
}

/// Keeps `AppSettings.lastActiveProjectPath` off the click-to-highlight frame.
///
/// Skills, MCP, Scheduled, and Settings selections never take a sequence number, and
/// a job consumes its sequence only when it actually writes. A Task selection can
/// therefore not discard a pending project write, while a stale job can never
/// overwrite a newer one.
@MainActor
final class LastActiveProjectRecorder {
    private let resolve: @MainActor (LastActiveProjectOwner) -> LastActiveProjectResolution
    private let persist: @MainActor (String?) -> Void
    private let suspendBeforeResolving: @MainActor () async -> Void
    private var scheduledSequence: UInt64 = 0
    private var appliedSequence: UInt64 = 0

    init(
        resolve: @escaping @MainActor (LastActiveProjectOwner) -> LastActiveProjectResolution,
        persist: @escaping @MainActor (String?) -> Void,
        suspendBeforeResolving: @escaping @MainActor () async -> Void = { await Task.yield() }
    ) {
        self.resolve = resolve
        self.persist = persist
        self.suspendBeforeResolving = suspendBeforeResolving
    }

    @discardableResult
    func record(for selection: SidebarItem?) -> Task<Void, Never>? {
        guard let owner = LastActiveProjectOwner(selection: selection) else {
            return nil
        }

        scheduledSequence &+= 1
        let sequence = scheduledSequence
        return Task { @MainActor in
            await suspendBeforeResolving()
            guard sequence > appliedSequence,
                  case .path(let path) = resolve(owner) else {
                return
            }
            appliedSequence = sequence
            persist(path)
        }
    }
}
