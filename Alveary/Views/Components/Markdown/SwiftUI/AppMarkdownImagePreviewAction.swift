import BlockInputKit
import Foundation
import SwiftUI

/// Host-provided handler that opens a clicked markdown image in the app's
/// image preview modal instead of the default `openURL` browser fallback.
/// Equality compares only the stable `id` and excludes the closure, so a host
/// re-injecting the action on every render does not invalidate the markdown
/// subtree's environment.
struct AppMarkdownImagePreviewAction: Equatable, Sendable {
    let id: String
    let perform: @MainActor @Sendable (BlockInputImage, URL?) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    @MainActor
    func callAsFunction(_ image: BlockInputImage, baseURL: URL?) {
        perform(image, baseURL)
    }
}

private struct AppMarkdownImagePreviewActionKey: EnvironmentKey {
    static let defaultValue: AppMarkdownImagePreviewAction? = nil
}

extension EnvironmentValues {
    /// When set, clicking a loaded markdown image block routes here; when nil,
    /// the block view falls back to opening the resolved remote URL.
    var appMarkdownImagePreviewAction: AppMarkdownImagePreviewAction? {
        get { self[AppMarkdownImagePreviewActionKey.self] }
        set { self[AppMarkdownImagePreviewActionKey.self] = newValue }
    }
}
