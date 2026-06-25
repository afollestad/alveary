import AppKit
import SwiftUI

@main
struct AlvearyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var appState = AppState()

    init() {
        _ = AppDI.component
    }

    var body: some Scene {
        Window("Alveary", id: "main") {
            ContentView(component: AppDI.component, appState: appState)
        }
        .defaultSize(width: 1440, height: 920)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Alveary") {
                    showAboutPanel()
                }
            }

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

            #if DEBUG
            CommandMenu("Developer") {
                Button("Show Fake Error Toast") {
                    appState.presentUnexpectedError(message: "Developer test error toast")
                }

                ViewRawTranscriptCommandButton()
                TriggerSessionHandoffCommandButton()
                CopyAppShotPreviewCommandButton()
                Button("Copy app-shot permission diagnostics") {
                    AppShotPermissionDiagnostics.copyToPasteboard()
                }
            }
            #endif
        }
        .modelContainer(AppDI.component.modelContainer)

        #if DEBUG
        WindowGroup("Raw Transcript", id: RawTranscriptWindowRequest.sceneID, for: RawTranscriptWindowRequest.self) { request in
            if let request = request.wrappedValue {
                RawTranscriptWindow(request: request)
            }
        }
        .defaultSize(width: 760, height: 640)
        .modelContainer(AppDI.component.modelContainer)
        #endif
    }

    @MainActor
    private func showAboutPanel() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: Self.aboutCredits
        ])
    }

    private static var aboutCredits: NSAttributedString {
        let text = "\nMade with ❤️ by Aidan Follestad\n\nWebsite | Ko-fi"
        let attributed = NSMutableAttributedString(string: text)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        attributed.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            range: NSRange(location: 0, length: attributed.length)
        )
        attributed.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: attributed.length)
        )
        addLink(to: attributed, label: "Website", urlString: "https://af.codes")
        addLink(to: attributed, label: "Ko-fi", urlString: "https://ko-fi.com/aidan1995")
        return attributed
    }

    private static func addLink(to attributed: NSMutableAttributedString, label: String, urlString: String) {
        guard
            let url = URL(string: urlString),
            let range = attributed.string.range(of: label)
        else {
            return
        }

        attributed.addAttributes(
            [
                .foregroundColor: NSColor.linkColor,
                .link: url,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ],
            range: NSRange(range, in: attributed.string)
        )
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

#if DEBUG
private struct ViewRawTranscriptCommandButton: View {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.rawTranscriptWindowRequest) private var rawTranscriptWindowRequest

    var body: some View {
        Button("View raw transcript") {
            guard let request = rawTranscriptWindowRequest?() else {
                return
            }
            openWindow(id: RawTranscriptWindowRequest.sceneID, value: request)
        }
        .disabled(rawTranscriptWindowRequest == nil)
    }
}

private struct TriggerSessionHandoffCommandButton: View {
    @FocusedValue(\.triggerSessionHandoffAction) private var triggerSessionHandoffAction

    var body: some View {
        Button("Trigger session handoff") {
            triggerSessionHandoffAction?()
        }
        .disabled(triggerSessionHandoffAction == nil)
    }
}

private struct CopyAppShotPreviewCommandButton: View {
    @FocusedValue(\.copyAppShotPreviewAction) private var copyAppShotPreviewAction

    var body: some View {
        Button("Copy app-shot transport preview") {
            copyAppShotPreviewAction?()
        }
        .disabled(copyAppShotPreviewAction == nil)
    }
}
#endif
