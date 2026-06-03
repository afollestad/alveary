import Foundation

enum ThreadCleanupAction: String, Codable, Sendable, CaseIterable {
    case archive
    case delete

    var label: String {
        switch self {
        case .archive:
            return "Archive"
        case .delete:
            return "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .archive:
            return "archivebox"
        case .delete:
            return "trash"
        }
    }
}
