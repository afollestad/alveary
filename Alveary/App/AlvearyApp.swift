import SwiftUI

@main
struct AlvearyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var appState = AppState()

    init() {
        _ = AppDI.resolver
    }

    var body: some Scene {
        Window("Alveary", id: "main") {
            ContentView(resolver: AppDI.resolver, appState: appState)
        }
        .defaultSize(width: 1440, height: 920)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Project...") {
                    appState.openNewProjectFlow()
                }
                .keyboardShortcut(.addProject)

                Button("New Thread") {
                    appState.startNewThreadFlow()
                }
                .keyboardShortcut(.newThread)

                NewConversationCommandButton()
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.openSettings()
                }
                .keyboardShortcut(.settings)
            }

            CommandGroup(after: .toolbar) {
                Button(appState.isRightPaneVisible ? "Hide Diff Viewer" : "Show Diff Viewer") {
                    appState.toggleRightPane()
                }
                .keyboardShortcut(.toggleDiffViewer)

                ToggleTerminalPaneCommandButton(appState: appState)

                Divider()
            }
        }
        .modelContainer(AppDI.resolver.modelContainer())
    }
}

/// Reads the thread-scoped `newConversationAction` focused value so the ⌘T
/// menu item is automatically disabled when no `ThreadDetailView` is mounted.
/// The binding lives here (rather than inline inside `commands`) so
/// `@FocusedValue` can participate in view invalidation.
private struct NewConversationCommandButton: View {
    @FocusedValue(\.newConversationAction) private var newConversationAction

    var body: some View {
        Button("New Conversation") {
            newConversationAction?()
        }
        .keyboardShortcut(.newConversation)
        .disabled(newConversationAction == nil)
    }
}

/// Reads the root-scoped `toggleTerminalPaneAction` focused value so the ⇧⌘T
/// menu item dispatches through the same `ensureSelection()`-then-flip helper
/// as the toolbar button. The publisher is `ContentView`, which is always the
/// main window's content, so the button is only disabled before the window
/// mounts.
private struct ToggleTerminalPaneCommandButton: View {
    // Plain stored property, not `@Bindable`: the menu button only reads
    // `appState.isTerminalPaneVisible` to flip its title and never creates a
    // `$`-binding, and `@Observable` tracking in `body` already invalidates the
    // view on change.
    var appState: AppState
    @FocusedValue(\.toggleTerminalPaneAction) private var toggleAction

    var body: some View {
        Button(appState.isTerminalPaneVisible ? "Hide Terminal" : "Show Terminal") {
            toggleAction?()
        }
        .keyboardShortcut(.toggleTerminalPane)
        .disabled(toggleAction == nil)
    }
}
