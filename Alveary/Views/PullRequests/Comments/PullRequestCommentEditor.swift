import SwiftUI

/// One comment-composing session. The pull-request surfaces keep their own name for
/// the shared `AppMarkdownDraft` box, which is what `PullRequestCommentEditor` and
/// every other markdown host in the app write into.
typealias PullRequestCommentDraftBox = AppMarkdownDraft

/// BlockInputKit-backed markdown editor shared by the inline diff composer and the
/// review footer. Composer-only features (completions, slash commands, drops) stay
/// off; the height grows with content up to a cap, then scrolls internally.
struct PullRequestCommentEditor: View {
    let draft: PullRequestCommentDraftBox
    let placeholder: String
    /// Visible lines before the editor grows. Comments keep two; the PR
    /// description opens at four, matching how much more it usually holds.
    var minimumVisibleLineCount = 2
    var isFocused: Binding<Bool>?
    /// Fired on Cmd+Return inside the editor. Hosts run their primary save/submit
    /// action here, including its enablement guard — the shortcut must never
    /// bypass a disabled Save/Submit button.
    var onSubmit: (() -> Void)?
    /// Fired on Escape inside the editor; hosts run the same action as their
    /// Cancel button.
    var onCancel: (() -> Void)?

    var body: some View {
        AppMarkdownEditor(
            draft: draft,
            placeholder: placeholder,
            sizing: .growsToLineCount(minimum: minimumVisibleLineCount, maximum: 10),
            isFocused: isFocused,
            onSubmit: onSubmit,
            onCancel: onCancel
        )
    }
}
