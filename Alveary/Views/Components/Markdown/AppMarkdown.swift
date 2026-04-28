import Foundation
import SwiftUI

let markdownInlineCodeFontScale: CGFloat = 0.94

enum AppMarkdownInlineCodeStyle {
    case standard
    case userBubble
    /// Accent-derived palette used by composer surfaces. The live input field draws
    /// chips directly from `AppMarkdownCodeBlockPalette.composerChip*`, and queue
    /// items render through this style so they match composer chrome.
    case composer
}

struct AppMarkdownTypography {
    // Defaults preserve shared markdown surfaces; transcript callers inject settings-backed values.
    enum FontLevel {
        case title1
        case title2
        case headline
        case subheadline
        case body
        case codeBlock
        case inlineCode
    }

    var title1 = Font.title2
    var title2 = Font.title3
    var headline = Font.headline
    var subheadline = Font.subheadline
    var body = Font.body
    var codeBlock = Font.system(.caption, design: .monospaced)
    var inlineCode = Font.system(.body, design: .monospaced)

    func swiftUIFont(_ level: FontLevel) -> Font {
        switch level {
        case .title1:
            return title1
        case .title2:
            return title2
        case .headline:
            return headline
        case .subheadline:
            return subheadline
        case .body:
            return body
        case .codeBlock:
            return codeBlock
        case .inlineCode:
            return inlineCode
        }
    }
}

private struct AppMarkdownTypographyKey: EnvironmentKey {
    static let defaultValue = AppMarkdownTypography()
}

extension EnvironmentValues {
    var appMarkdownTypography: AppMarkdownTypography {
        get { self[AppMarkdownTypographyKey.self] }
        set { self[AppMarkdownTypographyKey.self] = newValue }
    }
}

extension View {
    func appMarkdownFont(_ level: AppMarkdownTypography.FontLevel) -> some View {
        modifier(AppMarkdownFontModifier(level: level))
    }
}

private struct AppMarkdownFontModifier: ViewModifier {
    let level: AppMarkdownTypography.FontLevel

    @Environment(\.appMarkdownTypography) private var typography

    func body(content: Content) -> some View {
        content.font(typography.swiftUIFont(level))
    }
}

struct AppMarkdownText: View {
    let markdown: String
    var baseURL: URL?
    var foregroundColor: Color?
    var inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard
    var composerChipProvider: ((String) -> [AppTextEditorChip])?
    var taskStateScope: String?

    var body: some View {
        Group {
            if let foregroundColor {
                content.foregroundStyle(foregroundColor)
            } else {
                content
            }
        }
    }

    private var content: some View {
        let document = AppMarkdownDocumentCache.document(
            markdown: markdown,
            context: AppMarkdownDocumentCacheContext(
                baseURL: baseURL,
                inlineCodeStyle: inlineCodeStyle,
                hasComposerChipProvider: composerChipProvider != nil,
                taskStateScope: taskStateScope
            )
        ) {
            let parser = AppMarkdownParser(
                baseURL: baseURL,
                composerChipProvider: composerChipProvider
            )
            return parser.documentPreservingSource(for: markdown)
        }
        return AppMarkdownRenderer(document: document, inlineCodeStyle: inlineCodeStyle)
    }
}
