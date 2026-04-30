enum DiffViewerMode: String, Codable, Sendable, Equatable, CaseIterable {
    case currentChanges
    case commits

    var title: String {
        switch self {
        case .currentChanges:
            return "Current changes"
        case .commits:
            return "Commits"
        }
    }
}
