import SwiftUI

// Published by `ChatInputField` via `.focusedSceneValue` so sibling views (notably the
// sidebar) can release the composer's first-responder when they take keyboard focus.
// Without this, the composer's `@FocusState` remains `true` after the user clicks a
// sidebar row, and `syncFocusIfNeeded()` in the AppKit bridge keeps reclaiming the
// NSTextView as first responder, so arrow keys never reach the sidebar.
struct ChatComposerFocusKey: FocusedValueKey {
    typealias Value = FocusState<Bool>.Binding
}

extension FocusedValues {
    var chatComposerFocus: FocusState<Bool>.Binding? {
        get { self[ChatComposerFocusKey.self] }
        set { self[ChatComposerFocusKey.self] = newValue }
    }
}
