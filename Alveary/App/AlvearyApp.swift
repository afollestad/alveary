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
                Button("Add a Project...") {
                    appState.openNewProjectFlow()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("New Thread") {
                    appState.startNewThreadFlow()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button(appState.isRightPaneVisible ? "Hide Diff Viewer" : "Show Diff Viewer") {
                    appState.isRightPaneVisible.toggle()
                }
                .keyboardShortcut(.toggleDiffViewer)

                Divider()
            }
        }
        .modelContainer(AppDI.resolver.modelContainer())
    }
}
