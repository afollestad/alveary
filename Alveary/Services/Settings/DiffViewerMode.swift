enum DiffViewerMode: String, Codable, Sendable, Equatable, CaseIterable {
    case currentChanges
    case commits

    /// Keep these short. They label `fixedSize` chips in the diff viewer's header, which clips
    /// rather than compresses: the chip row plus every header action has to fit the 320pt minimum
    /// pane width or the trailing action is silently clipped away. "Current changes" is what made
    /// Discard unreachable, and is why this reads "Changes".
    var title: String {
        switch self {
        case .currentChanges:
            return "Changes"
        case .commits:
            return "Commits"
        }
    }
}
