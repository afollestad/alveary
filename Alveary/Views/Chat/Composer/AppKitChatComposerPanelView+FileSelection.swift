import AppKit

@MainActor
extension AppKitChatComposerPanelView {
    func panelTaskWorkspaceConfiguration(
        _ workspace: ChatComposerActionRowView.TaskWorkspaceConfiguration?
    ) -> ChatComposerActionRowView.TaskWorkspaceConfiguration? {
        guard let workspace else {
            return nil
        }
        return .init(
            primaryRoot: workspace.primaryRoot,
            grantedRoots: workspace.grantedRoots,
            ownershipStrategy: workspace.ownershipStrategy,
            canEdit: workspace.canEdit,
            disabledTooltip: workspace.disabledTooltip,
            onAddFolders: { [weak self] _ in
                self?.presentTaskWorkspaceFolderPicker(onSelect: workspace.onAddFolders)
            },
            onRemoveGrant: workspace.onRemoveGrant
        )
    }

    func presentTaskWorkspaceFolderPicker(onSelect: @escaping ([URL]) -> Void) {
        guard configuration?.bodyConfiguration.isVoiceInteractionLocked != true else {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.prompt = "Grant Access"
        panel.message = "Choose folders this task may access in addition to its private workspace."

        guard let window else {
            guard panel.runModal() == .OK else {
                return
            }
            guard configuration?.bodyConfiguration.isVoiceInteractionLocked != true else {
                return
            }
            onSelect(panel.urls)
            return
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK,
                  self?.configuration?.bodyConfiguration.isVoiceInteractionLocked != true else {
                return
            }
            onSelect(panel.urls)
        }
    }

    func presentPhotosAndFilesPicker() {
        guard configuration?.bodyConfiguration.isVoiceInteractionLocked != true else {
            return
        }
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
        guard !urls.isEmpty,
              configuration?.bodyConfiguration.isVoiceInteractionLocked != true else {
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
