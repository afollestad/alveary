import Foundation
import SwiftUI

struct AppMarkdownRenderer: View {
    let document: AppMarkdownDocument
    let inlineCodeStyle: AppMarkdownInlineCodeStyle

    var body: some View {
        AppMarkdownBlockContent(
            content: document.content,
            taskStateNamespace: document.taskStateNamespace,
            inlineCodeStyle: inlineCodeStyle
        )
        .textSelection(.enabled)
    }
}
