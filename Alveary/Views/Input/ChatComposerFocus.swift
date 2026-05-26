import SwiftUI

struct ChatComposerFocusHandle {
    let claim: @MainActor () -> Void
    let release: @MainActor () -> Void
}

// Published through `.focusedSceneValue` so sibling views can release the
// composer before claiming their own keyboard surface.
struct ChatComposerFocusKey: FocusedValueKey {
    typealias Value = ChatComposerFocusHandle
}

extension FocusedValues {
    var chatComposerFocus: ChatComposerFocusHandle? {
        get { self[ChatComposerFocusKey.self] }
        set { self[ChatComposerFocusKey.self] = newValue }
    }
}
