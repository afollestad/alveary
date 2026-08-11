import Foundation

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
