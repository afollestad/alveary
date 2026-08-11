import SwiftData
import SwiftUI

/// Published by `ThreadDetailView` so `AlvearyApp.commands` can expose a ⌘T
/// "New Conversation" menu item that is only enabled while a thread view is
/// mounted. `ThreadDetailView.createConversation()` is private and scoped to
/// the active thread, so routing the menu through a `FocusedValue` keeps the
/// command aware of the current thread without duplicating that logic or
/// plumbing a new `CommandRequest` case through `ContentView+Commands.swift`.
///
/// Like `DiffViewerCommand`, equality deliberately excludes the closure and
/// compares the publishing thread's identity instead. `ContentView` reads this
/// focused value for the toolbar `+` button; a bare-closure value can never
/// compare equal, so every `ThreadDetailView` body evaluation would invalidate
/// `ContentView`, which re-renders `ThreadDetailView`, which republishes —
/// a frame-rate render loop across the whole window.
struct NewConversationAction: Equatable {
    let threadID: PersistentIdentifier
    let perform: @MainActor () -> Void

    static func == (lhs: NewConversationAction, rhs: NewConversationAction) -> Bool {
        lhs.threadID == rhs.threadID
    }

    @MainActor
    func callAsFunction() {
        perform()
    }
}

struct NewConversationActionKey: FocusedValueKey {
    typealias Value = NewConversationAction
}

/// Published by `ContentView` so the ⇧⌘T "Show/Hide Terminal" menu item can
/// dispatch through the same `toggleTerminalPane()` helper the toolbar button
/// calls directly — that helper creates or selects a default shell session
/// before flipping `isTerminalPaneVisible`. A direct visibility mutation from
/// the menu cannot do that because the terminal manager is view-local `@State`.
struct ToggleTerminalPaneActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

/// Published by `ContentView` so the ⇧⌘P "Linked Pull Requests" menu item can run
/// the same action the toolbar button does — which reads the selected thread's
/// links and either opens a pane or a view-local popover, neither reachable from
/// the scene menu. A bare closure is correct here, unlike `DiffViewerCommand`:
/// only the menu reads this value, so no ancestor of the publisher can be
/// invalidated by a closure that never compares equal.
struct TogglePullRequestsActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

/// Published by `ContentView` so the ⇧⌘D menu item can render the toggle's
/// current sense ("Show" vs "Hide") and run the same `toggleDiffViewer` helper.
///
/// `ContentView` rebuilds this on every body pass with a fresh closure, so
/// equality compares only `title` — the one thing the menu item renders. A bare
/// closure, or an `==` that included it, would invalidate `DiffViewerCommandButton`
/// on every render of the publisher.
struct DiffViewerCommand: Equatable {
    let title: String
    let action: @MainActor () -> Void

    static func == (lhs: DiffViewerCommand, rhs: DiffViewerCommand) -> Bool {
        lhs.title == rhs.title
    }
}

struct DiffViewerCommandKey: FocusedValueKey {
    typealias Value = DiffViewerCommand
}

/// Published by `ChatView` so the debug-only Developer menu can trigger a
/// session handoff with automatic-style steering behavior.
struct TriggerSessionHandoffActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

#if DEBUG
/// Published by `ChatView` so the debug-only Developer menu can copy the
/// generated provider transport body for staged app shots without sending.
struct CopyAppShotPreviewActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}

/// Published by `ThreadDetailView` so the debug-only Developer menu can open a
/// raw transcript window for the currently selected conversation.
struct RawTranscriptWindowRequestKey: FocusedValueKey {
    typealias Value = @MainActor () -> RawTranscriptWindowRequest
}
#endif

extension FocusedValues {
    var newConversationAction: NewConversationActionKey.Value? {
        get { self[NewConversationActionKey.self] }
        set { self[NewConversationActionKey.self] = newValue }
    }

    var toggleTerminalPaneAction: ToggleTerminalPaneActionKey.Value? {
        get { self[ToggleTerminalPaneActionKey.self] }
        set { self[ToggleTerminalPaneActionKey.self] = newValue }
    }

    var diffViewerCommand: DiffViewerCommandKey.Value? {
        get { self[DiffViewerCommandKey.self] }
        set { self[DiffViewerCommandKey.self] = newValue }
    }

    var togglePullRequestsAction: TogglePullRequestsActionKey.Value? {
        get { self[TogglePullRequestsActionKey.self] }
        set { self[TogglePullRequestsActionKey.self] = newValue }
    }

    var triggerSessionHandoffAction: TriggerSessionHandoffActionKey.Value? {
        get { self[TriggerSessionHandoffActionKey.self] }
        set { self[TriggerSessionHandoffActionKey.self] = newValue }
    }

    #if DEBUG
    var copyAppShotPreviewAction: CopyAppShotPreviewActionKey.Value? {
        get { self[CopyAppShotPreviewActionKey.self] }
        set { self[CopyAppShotPreviewActionKey.self] = newValue }
    }

    var rawTranscriptWindowRequest: RawTranscriptWindowRequestKey.Value? {
        get { self[RawTranscriptWindowRequestKey.self] }
        set { self[RawTranscriptWindowRequestKey.self] = newValue }
    }
    #endif
}
