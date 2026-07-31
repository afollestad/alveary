enum DiffViewerMode: String, Codable, Sendable, Equatable, CaseIterable {
    case currentChanges
    case commits

    var title: String {
        switch self {
        case .currentChanges:
            return "Changes"
        case .commits:
            return "Commits"
        }
    }
}
