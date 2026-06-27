import AppKit

@MainActor
extension AppKitChatComposerPanelView {
    func presentPhotosAndFilesPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.prompt = "Add"
        panel.message = "Choose photos or files to add to the message."

        guard let window else {
            let response = panel.runModal()
            guard response == .OK else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.insertSelectedLocalFileURLs(panel.urls)
            }
            return
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.insertSelectedLocalFileURLs(panel.urls)
            }
        }
    }

    func insertSelectedLocalFileURLs(_ urls: [URL]) async {
        guard !urls.isEmpty else {
            return
        }
        switch await configuration?.bodyConfiguration.onLocalFileURLsSelected(urls) ?? .handled {
        case .useDefault:
            break
        case .handled:
            break
        case .insertDefault(let remainingURLs):
            _ = remainingURLs
        }
        editorController.view?.focusEditor()
    }
}
