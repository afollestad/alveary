import SwiftUI

/// Published by `ThreadDetailView` so `AlvearyApp.commands` can expose a ⌘T
/// "New Conversation" menu item that is only enabled while a thread view is
/// mounted. `ThreadDetailView.createConversation()` is private and scoped to
/// the active thread, so routing the menu through a `FocusedValue` keeps the
/// command aware of the current thread without duplicating that logic or
/// plumbing a new `CommandRequest` case through `ContentView+Commands.swift`.
struct NewConversationActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

extension FocusedValues {
    var newConversationAction: NewConversationActionKey.Value? {
        get { self[NewConversationActionKey.self] }
        set { self[NewConversationActionKey.self] = newValue }
    }
}
