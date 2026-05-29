@preconcurrency import AppKit
import BlockInputKit

extension AppKitChatComposerEditorController {
    func configureBlockInput(_ configuration: AppKitChatComposerBodyConfiguration) {
        let bridgeConfiguration = blockInputBridgeConfiguration(for: configuration)
        if let bridgeController {
            bridgeController.configure(bridgeConfiguration)
        } else {
            let controller = BlockInputComposerBridgeController(configuration: bridgeConfiguration)
            bridgeController = controller
        }
    }

    func blockInputBridgeConfiguration(
        for configuration: AppKitChatComposerBodyConfiguration
    ) -> BlockInputComposerBridgeConfiguration {
        let presentation = presentation(for: configuration)
        return BlockInputComposerBridgeConfiguration(
            markdown: configuration.text,
            markdownRevision: configuration.inputDraftRevision,
            placeholder: presentation.placeholder,
            isEditable: !presentation.isTextEditorDisabled,
            disabledCursor: configuration.isProjectTrustBlocked ? .operationNotAllowed : nil,
            editorHorizontalInset: Self.editorHorizontalPadding,
            editorVerticalInset: Self.editorVerticalPadding,
            editorRoundedCorners: configuration.hasQueuedMessages ? .bottom : .all,
            location: BlockInputComposerLocation(effectiveProjectDirectory: configuration.workingDirectory),
            loadFileCompletions: configuration.loadFileCompletions,
            loadSkillCompletions: configuration.loadSkillCompletions,
            keyboardShortcuts: blockInputKeyboardShortcuts(),
            completionPopupOverlayProvider: { [weak self] context in
                self?.blockInputCompletionPopupOverlay(context: context)
            },
            modalOverlayProvider: { [weak self] context in
                self?.blockInputModalOverlay(context: context)
            },
            onDocumentMutation: { _, isEffectivelyEmpty in
                configuration.onBlockInputMutation(isEffectivelyEmpty)
            },
            onDocumentChange: configuration.onBlockInputDocumentChange,
            onPreferredHeightTransition: { [weak self] transition in
                self?.handlePreferredHeightTransition(transition)
            }
        )
    }

    func blockInputModalOverlay(
        context: BlockInputModalOverlayContext
    ) -> BlockInputModalOverlay? {
        guard let surface = enclosingChatSurfaceView() else {
            return nil
        }
        return BlockInputModalOverlay(
            container: surface,
            frame: context.modalFrame(
                in: surface,
                horizontalOffset: Self.modalHorizontalOffset,
                verticalSpacing: Self.modalVerticalSpacing
            )
        )
    }

    func blockInputCompletionPopupOverlay(
        context: BlockInputCompletionPopupOverlayContext
    ) -> BlockInputCompletionPopupOverlay? {
        guard let surface = enclosingChatSurfaceView() else {
            return nil
        }
        let editorFrame = context.editorFrame(in: surface)
        return BlockInputCompletionPopupOverlay(
            container: surface,
            frame: NSRect(
                x: editorFrame.minX,
                y: editorFrame.minY - context.popupSize.height - Self.autocompleteVerticalOffset,
                width: editorFrame.width,
                height: context.popupSize.height
            )
        )
    }

    func enclosingChatSurfaceView() -> AppKitChatSurfaceView? {
        var candidate = view?.superview
        while let view = candidate {
            if let surface = view as? AppKitChatSurfaceView {
                return surface
            }
            candidate = view.superview
        }
        return nil
    }

    func installDraftSnapshotProvider(_ configuration: AppKitChatComposerBodyConfiguration) {
        configuration.onDraftSnapshotProviderChange { [weak self] in
            guard let self,
                  let bridgeController = self.bridgeController else {
                return ComposerDraft(
                    text: configuration.text,
                    source: .blockInputMarkdown,
                    isEffectivelyEmpty: configuration.isTextEffectivelyEmpty
                )
            }

            let document = bridgeController.documentStore.document
            return ComposerDraft(
                text: bridgeController.currentMarkdown(),
                source: .blockInputMarkdown,
                isEffectivelyEmpty: document.isEffectivelyEmpty
            )
        }
    }

    func blockInputKeyboardShortcuts() -> [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] {
        [
            .returnKey: { [weak self] _ in
                self?.handleBlockInputReturn(usesAlternateBehavior: false) ?? .handled
            },
            .shiftReturn: { _ in .ignored },
            .optionReturn: { [weak self] _ in
                self?.handleBlockInputReturn(usesAlternateBehavior: true) ?? .handled
            },
            BlockInputKeyboardShortcut(key: .escape): { [weak self] _ in
                self?.handleBlockInputEscape() ?? .ignored
            }
        ]
    }

    func handleBlockInputReturn(
        usesAlternateBehavior: Bool
    ) -> BlockInputKeyboardShortcutResult {
        guard let configuration else {
            return .handled
        }
        switch configuration.mode {
        case .progressOnly:
            return .handled
        case .busy(let canStop):
            performBusyReturnAction(
                canStop: canStop,
                usesAlternateBehavior: usesAlternateBehavior,
                configuration: configuration
            )
            return .handled
        case .idle:
            performSubmit(configuration: configuration)
            return .handled
        }
    }

    func handleBlockInputEscape() -> BlockInputKeyboardShortcutResult {
        guard let configuration else {
            return .ignored
        }
        guard presentation(for: configuration).canUseEscapeToStop else {
            return .ignored
        }
        if configuration.isStopConfirmationArmed {
            performStop(configuration: configuration)
        } else {
            armStopConfirmation(configuration: configuration)
        }
        return .handled
    }
}
