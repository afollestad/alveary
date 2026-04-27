import Foundation
import SwiftUI

struct AppMarkdownDocument: Equatable {
    let content: AttributedString
    let taskStateNamespace: String

    init(
        content: AttributedString,
        taskStateNamespace: String = ""
    ) {
        self.content = content
        self.taskStateNamespace = taskStateNamespace
    }
}

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
