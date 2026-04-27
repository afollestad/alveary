import Foundation
import SwiftUI

struct AppMarkdownCodeBlock: View {
    let code: String
    let languageHint: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal) {
            Text(attributedCode)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .background(AppMarkdownCodeBlockPalette.fillColor(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppMarkdownCodeBlockPalette.borderColor(for: colorScheme), lineWidth: 1)
        )
    }

    private var attributedCode: AttributedString {
        SyntaxHighlighter.highlighted(code, language: languageHint ?? "", colorScheme: colorScheme)
    }
}
