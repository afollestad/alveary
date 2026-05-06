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
        let document: AppMarkdownDocument
        let appearance: NSAppearance
    }

    static func measurement(_ context: Context) -> AppKitMarkdownLayoutMeasurement? {
        let configuration = context.configuration
        let key = AppKitMarkdownPreparedLayoutKey(
            rowID: configuration.id,
            markdown: configuration.markdown,
            role: cacheRole(for: configuration.role),
            availableWidth: context.markdownWidth,
            bubbleMaxWidth: configuration.bubbleMaxWidth,
            typography: configuration.typography,
            inlineCodeStyle: context.inlineCodeStyle,
            appearanceName: markdownAppearanceName(for: context.appearance),
            isExpanded: context.isExpanded,
            showsRetry: configuration.showsRetry
        )
        if let cached = textBubblePreparedLayoutCache.measurement(for: key) {
            return cached.fallbackRequired ? nil : cached
        }

        let measurement = AppKitMarkdownLayoutMeasurer(
            document: context.document,
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

    private static func cacheRole(for role: AppKitTranscriptTextBubbleRowView.Role) -> String {
        switch role {
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        }
    }

    private static func markdownColorScheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private static func markdownAppearanceName(for appearance: NSAppearance) -> String {
        appearance.bestMatch(from: [.darkAqua, .aqua])?.rawValue ?? appearance.name.rawValue
    }
}

extension AppKitTranscriptTextBubbleRowView {
    func inlineCodeStyle(for role: Role) -> AppMarkdownInlineCodeStyle {
        switch role {
        case .user:
            return .userBubble
        case .assistant:
            return .standard
        }
    }
}
