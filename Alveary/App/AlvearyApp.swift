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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Thread") {
                    appState.startNewThreadFlow()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Project...") {
                    appState.openNewProjectFlow()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .modelContainer(AppDI.resolver.modelContainer())
    }
}
