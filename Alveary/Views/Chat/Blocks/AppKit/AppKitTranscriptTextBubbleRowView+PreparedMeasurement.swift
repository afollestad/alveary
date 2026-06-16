@preconcurrency import AppKit
import SwiftUI

@MainActor
private let textBubblePreparedLayoutCache = AppKitMarkdownPreparedLayoutCache()

@MainActor
/// Bridges text-bubble layout inputs to the renderer-neutral markdown measurer
/// and preserves the old hydrated-view measurement as the fallback path.
enum TextBubblePreparedMeasurement {
    struct Context {
        let configuration: AppKitTranscriptTextBubbleRowView.Configuration
        let isExpanded: Bool
        let markdownWidth: CGFloat
        let inlineCodeStyle: AppMarkdownInlineCodeStyle
        let appearance: NSAppearance

        var key: AppKitMarkdownPreparedLayoutKey {
            AppKitMarkdownPreparedLayoutKey(
                rowID: configuration.id,
                markdown: configuration.markdown,
                role: TextBubblePreparedMeasurement.cacheRole(for: configuration.role),
                availableWidth: markdownWidth,
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography,
                inlineCodeStyle: inlineCodeStyle,
                appearanceName: TextBubblePreparedMeasurement.markdownAppearanceName(for: appearance),
                isExpanded: isExpanded,
                showsRetry: configuration.showsRetry
            )
        }

        var documentCacheContext: AppMarkdownDocumentCacheContext {
            AppMarkdownDocumentCacheContext(
                baseURL: nil,
                inlineCodeStyle: inlineCodeStyle,
                composerChipMode: configuration.role == .user ? .composer : .none,
                taskStateScope: configuration.id
            )
        }
    }

    static func cachedMeasurement(for key: AppKitMarkdownPreparedLayoutKey) -> AppKitMarkdownLayoutMeasurement? {
        if let cached = textBubblePreparedLayoutCache.measurement(for: key) {
            return cached.fallbackRequired ? nil : cached
        }
        return nil
    }

    static func measurement(
        _ context: Context,
        document: AppMarkdownDocument
    ) -> AppKitMarkdownLayoutMeasurement? {
        let key = context.key
        if let cached = cachedMeasurement(for: key) {
            return cached
        }
        let configuration = context.configuration
        let measurement = AppKitMarkdownLayoutMeasurer(
            document: document,
            inlineCodeStyle: context.inlineCodeStyle,
            typography: configuration.typography,
            colorScheme: markdownColorScheme(for: context.appearance)
        )
        .measure(width: context.markdownWidth)
        textBubblePreparedLayoutCache.insert(
            measurement,
            for: key,
            cost: configuration.markdown.utf8.count + Int(ceil(context.markdownWidth)) + 128
        )
        return measurement.fallbackRequired ? nil : measurement
    }

    nonisolated static func cacheRole(for role: AppKitTranscriptTextBubbleRowView.Role) -> String {
        switch role {
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        }
    }

    private nonisolated static func markdownColorScheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private nonisolated static func markdownAppearanceName(for appearance: NSAppearance) -> String {
        appearance.bestMatch(from: [.darkAqua, .aqua])?.rawValue ?? appearance.name.rawValue
    }
}

extension AppKitTranscriptTextBubbleRowView {
    func inlineCodeStyle(for role: Role) -> AppMarkdownInlineCodeStyle {
        switch role {
        case .user:
            return .userBubble
        case .assistant:
            return .assistantBubble
        }
    }
}
