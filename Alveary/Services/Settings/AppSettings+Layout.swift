extension AppSettings {
    static func normalizedDiffViewerMode(_ rawValue: String?) -> DiffViewerMode {
        guard let rawValue,
              let mode = DiffViewerMode(rawValue: rawValue) else {
            return defaultDiffViewerMode
        }
        return mode
    }

    static func normalizedRightPaneWidth(_ width: Double) -> Double {
        min(max(width, supportedRightPaneWidthRange.lowerBound), supportedRightPaneWidthRange.upperBound)
    }
}
