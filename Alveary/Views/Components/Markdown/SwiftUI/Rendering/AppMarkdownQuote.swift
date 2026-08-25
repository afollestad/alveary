import Foundation
import SwiftUI

private let appMarkdownQuoteBarWidth: CGFloat = 3
private let appMarkdownQuoteBarSpacing: CGFloat = 10

/// A blockquote, and — when it opens with a `[!KIND]` marker — one of GitHub's alerts.
///
/// Both live in one view so `AppMarkdownBlock`'s switch keeps a single `.blockQuote` branch; the
/// two shapes differ only in the bar's tint and the presence of a header row, and Swift solves a
/// `body` as a whole (see the type-check budget rules in `Alveary/Views/AGENTS.md`).
///
/// It takes an `AttributedString` rather than the generic `AttributedStringProtocol` the sibling
/// block views use: an alert hands its marker-stripped *copy* downstream, and two generic
/// instantiations cannot share one `@ViewBuilder` branch. The call site converts, exactly as
/// `AppMarkdownList` already does per item.
struct AppMarkdownQuote: View {
    let intent: PresentationIntent.IntentType?
    let content: AttributedString
    let taskStateNamespace: String
    let path: String
    let inlineCodeStyle: AppMarkdownInlineCodeStyle

    var body: some View {
        let alert = AppMarkdownAlert(content: content)
        HStack(alignment: .top, spacing: appMarkdownQuoteBarSpacing) {
            Rectangle()
                .fill(barColor(for: alert?.kind))
                .frame(width: appMarkdownQuoteBarWidth)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: AppMarkdownAlertMetrics.headerSpacing) {
                if let alert {
                    AppMarkdownAlertHeader(kind: alert.kind)
                }
                if alert?.hasBody ?? true {
                    AppMarkdownBlockContent(
                        content: alert?.contentWithoutMarker ?? content,
                        parent: intent,
                        taskStateNamespace: taskStateNamespace,
                        path: path,
                        inlineCodeStyle: inlineCodeStyle
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func barColor(for kind: AppMarkdownAlertKind?) -> Color {
        guard let kind else {
            return Color.secondary.opacity(0.45)
        }
        return Color(nsColor: kind.accentNSColor)
    }
}

/// The icon-and-title row above an alert's body. The glyph inherits the markdown body font so it
/// scales with settings-backed transcript typography, and hides itself from VoiceOver because the
/// title beside it already names the alert.
private struct AppMarkdownAlertHeader: View {
    let kind: AppMarkdownAlertKind

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppMarkdownAlertMetrics.iconSpacing) {
            Image(systemName: kind.symbolName)
                .accessibilityHidden(true)
            Text(kind.title)
                .fontWeight(.semibold)
        }
        .foregroundStyle(Color(nsColor: kind.accentNSColor))
    }
}
