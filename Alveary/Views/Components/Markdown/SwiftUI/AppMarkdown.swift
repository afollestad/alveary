import Foundation
import SwiftUI

private let deferredMarkdownDocumentSwapDelay: UInt64 = 250_000_000

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
                composerChipMode: composerChipProvider == nil ? .none : .composer,
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

struct DeferredAppMarkdownText: View {
    let markdown: String
    var baseURL: URL?
    var foregroundColor: Color?
    var inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard
    var composerChipMode: AppMarkdownComposerChipMode = .none
    var taskStateScope: String?
    var placeholder: String?

    @State private var renderedDocument: DeferredAppMarkdownRenderedDocument?

    var body: some View {
        Group {
            if let renderedDocument, renderedDocument.taskID == taskID {
                rendered(renderedDocument.document)
            } else if let placeholder {
                AppMarkdownText(
                    markdown: placeholder,
                    baseURL: baseURL,
                    foregroundColor: foregroundColor,
                    inlineCodeStyle: inlineCodeStyle,
                    composerChipProvider: composerChipProvider,
                    taskStateScope: taskStateScope
                )
            } else {
                Text(markdown)
                    .textSelection(.enabled)
            }
        }
        .task(id: taskID) {
            let currentTaskID = taskID
            let parsedDocument = await AppMarkdownDocumentCache.document(markdown: markdown, context: cacheContext)
            try? await Task.sleep(nanoseconds: deferredMarkdownDocumentSwapDelay)
            guard !Task.isCancelled,
                  taskID == currentTaskID else {
                return
            }
            renderedDocument = DeferredAppMarkdownRenderedDocument(
                taskID: currentTaskID,
                document: parsedDocument
            )
        }
    }

    private var taskID: String {
        [
            baseURL?.absoluteString ?? "",
            inlineCodeStyle.cacheKey,
            composerChipMode.cacheKey,
            taskStateScope ?? "",
            markdown
        ].joined(separator: "|")
    }

    private var cacheContext: AppMarkdownDocumentCacheContext {
        AppMarkdownDocumentCacheContext(
            baseURL: baseURL,
            inlineCodeStyle: inlineCodeStyle,
            composerChipMode: composerChipMode,
            taskStateScope: taskStateScope
        )
    }

    @ViewBuilder
    private func rendered(_ document: AppMarkdownDocument) -> some View {
        if let foregroundColor {
            AppMarkdownRenderer(document: document, inlineCodeStyle: inlineCodeStyle)
                .foregroundStyle(foregroundColor)
        } else {
            AppMarkdownRenderer(document: document, inlineCodeStyle: inlineCodeStyle)
        }
    }

    private var composerChipProvider: ((String) -> [AppTextEditorChip])? {
        switch composerChipMode {
        case .none:
            return nil
        case .composer:
            return ChatComposerTextSupport.composerTextChips(in:)
        }
    }
}

private struct DeferredAppMarkdownRenderedDocument {
    let taskID: String
    let document: AppMarkdownDocument
}

private extension AppMarkdownComposerChipMode {
    var cacheKey: String {
        switch self {
        case .none: return "plain"
        case .composer: return "chips"
        }
    }
}
