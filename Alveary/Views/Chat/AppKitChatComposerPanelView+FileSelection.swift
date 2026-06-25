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
        let urlsToInsert: [URL]
        switch await configuration?.bodyConfiguration.onLocalFileURLsSelected(urls) ?? .useDefault {
        case .useDefault:
            urlsToInsert = urls
        case .handled:
            urlsToInsert = []
        case .insertDefault(let remainingURLs):
            urlsToInsert = remainingURLs
        }
        if !urlsToInsert.isEmpty {
            _ = editorController.view?.insertLocalFileURLs(urlsToInsert)
        }
        editorController.view?.focusEditor()
    }
}
