import Foundation
import SwiftData

struct ThreadRenameDraft: RenameDraft {
    let threadID: PersistentIdentifier
    let currentDisplayName: String
    var title: String

    var id: PersistentIdentifier {
        threadID
    }

    init(thread: AgentThread) {
        threadID = thread.persistentModelID
        currentDisplayName = thread.displayName()
        title = thread.displayName()
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        !trimmedTitle.isEmpty
    }

    var persistedName: String? {
        AgentThread.persistedName(from: title)
    }
}

enum SidebarThreadActionError: LocalizedError {
    case renameTargetMissing
    case renameFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .renameTargetMissing:
            return "Couldn't rename thread: it no longer exists"
        case .renameFailed(let error):
            return "Couldn't rename thread: \(error.localizedDescription)"
        }
    }
}
