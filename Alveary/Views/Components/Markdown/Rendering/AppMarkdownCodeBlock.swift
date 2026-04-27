import Foundation
import SwiftUI

struct AppMarkdownCodeBlock: View {
    let code: String
    let languageHint: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let attributedCode = attributedCode
        ScrollView(.horizontal) {
            codeBlockText(attributedCode: attributedCode)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func codeBlockText(attributedCode: AttributedString) -> some View {
        Text(attributedCode)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: true)
    }
}
