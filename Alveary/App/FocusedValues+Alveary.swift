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

/// Published by `ContentView` so the ⇧⌘T "Show/Hide Terminal" menu item can
/// dispatch through the same `toggleTerminalPane()` helper the toolbar button
/// calls directly — that helper invokes `TerminalManager.ensureSelection()`
/// before flipping `isTerminalPaneVisible`, which a plain
/// `AppState.toggleTerminalPane()` call from the menu could not do because the
/// terminal manager is view-local `@State`.
struct ToggleTerminalPaneActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

extension FocusedValues {
    var newConversationAction: NewConversationActionKey.Value? {
        get { self[NewConversationActionKey.self] }
        set { self[NewConversationActionKey.self] = newValue }
    }

    var toggleTerminalPaneAction: ToggleTerminalPaneActionKey.Value? {
        get { self[ToggleTerminalPaneActionKey.self] }
        set { self[ToggleTerminalPaneActionKey.self] = newValue }
    }
}
