import AppKit
import SwiftUI

struct TranscriptTypography: Equatable {
    let chatFontSize: CGFloat
    let codeFontFamily: String
    let codeFontSize: CGFloat

    init(settings: AppSettings = AppSettings()) {
        let settings = settings.normalized()
        chatFontSize = CGFloat(settings.chatFontSize)
        codeFontFamily = settings.codeFontFamily
        codeFontSize = CGFloat(settings.codeFontSize)
    }

    func font(_ level: TranscriptFontLevel, weight: Font.Weight = .regular) -> Font {
        .system(size: size(for: level), weight: weight)
    }

    var codeFont: Font {
        Font(codeNSFont)
    }

    var markdownTypography: AppMarkdownTypography {
        AppMarkdownTypography(
            title1: font(.title),
            title2: font(.title),
            headline: font(.headline),
            subheadline: font(.subheadline),
            body: font(.body),
            codeBlock: codeFont,
            inlineCode: codeFont
        )
    }

    private var codeNSFont: NSFont {
        NSFontManager.shared.font(
            withFamily: codeFontFamily,
            traits: [],
            weight: 5,
            size: codeFontSize
        ) ?? NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
    }

    func size(for level: TranscriptFontLevel) -> CGFloat {
        switch level {
        case .body:
            return chatFontSize
        case .title:
            return chatFontSize + 3
        case .headline:
            return chatFontSize + 1
        case .subheadline, .toolSummary:
            return max(chatFontSize - 1, 10)
        case .caption, .approvalBody:
            return max(chatFontSize - 2, 9)
        case .toolIcon, .toolStatusIcon:
            return 11
        }
    }
}

enum TranscriptFontLevel {
    case body
    case title
    case headline
    case subheadline
    case caption
    case toolSummary
    case approvalBody
    case toolIcon
    case toolStatusIcon
}

private struct TranscriptTypographyKey: EnvironmentKey {
    static let defaultValue = TranscriptTypography()
}

extension EnvironmentValues {
    var transcriptTypography: TranscriptTypography {
        get { self[TranscriptTypographyKey.self] }
        set { self[TranscriptTypographyKey.self] = newValue }
    }
}

extension View {
    func transcriptFont(_ level: TranscriptFontLevel, weight: Font.Weight = .regular) -> some View {
        modifier(TranscriptFontModifier(level: level, weight: weight))
    }

    func transcriptCodeFont() -> some View {
        modifier(TranscriptCodeFontModifier())
    }

    func transcriptMarkdownTypography() -> some View {
        // Keeps direct transcript block previews/snapshots aligned with the full transcript.
        modifier(TranscriptMarkdownTypographyModifier())
    }
}

private struct TranscriptFontModifier: ViewModifier {
    let level: TranscriptFontLevel
    let weight: Font.Weight

    @Environment(\.transcriptTypography) private var typography

    func body(content: Content) -> some View {
        content.font(typography.font(level, weight: weight))
    }
}

private struct TranscriptCodeFontModifier: ViewModifier {
    @Environment(\.transcriptTypography) private var typography

    func body(content: Content) -> some View {
        content.font(typography.codeFont)
    }
}

private struct TranscriptMarkdownTypographyModifier: ViewModifier {
    @Environment(\.transcriptTypography) private var typography

    func body(content: Content) -> some View {
        content.environment(\.appMarkdownTypography, typography.markdownTypography)
    }
}
