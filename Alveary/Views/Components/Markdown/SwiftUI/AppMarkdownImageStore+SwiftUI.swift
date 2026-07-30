import SwiftUI

private struct AppMarkdownImageStoreKey: EnvironmentKey {
    // nil resolves to `.shared` at read sites; EnvironmentKey.defaultValue is
    // nonisolated, so the main-actor singleton cannot be the default directly.
    static let defaultValue: AppMarkdownImageStore? = nil
}

extension EnvironmentValues {
    /// Markdown image store override; snapshot hosts inject a preloaded store so
    /// rendering stays deterministic without network access.
    var appMarkdownImageStore: AppMarkdownImageStore? {
        get { self[AppMarkdownImageStoreKey.self] }
        set { self[AppMarkdownImageStoreKey.self] = newValue }
    }
}
