@preconcurrency import AppKit
import BlockInputKit

extension AppKitChatComposerEditorController {
    func configureBlockInput(_ configuration: AppKitChatComposerBodyConfiguration) -> Bool {
        let bridgeConfiguration = blockInputBridgeConfiguration(for: configuration)
        if let bridgeController {
            return bridgeController.configure(bridgeConfiguration)
        } else {
            let controller = BlockInputComposerBridgeController(configuration: bridgeConfiguration)
            bridgeController = controller
            return false
        }
    }

    func blockInputBridgeConfiguration(
        for configuration: AppKitChatComposerBodyConfiguration
    ) -> BlockInputComposerBridgeConfiguration {
        let presentation = presentation(for: configuration)
        let hasAttachmentStrip = !configuration.attachments.isEmpty
        return BlockInputComposerBridgeConfiguration(
            markdown: configuration.text,
            markdownRevision: configuration.inputDraftRevision,
            placeholder: presentation.placeholder,
            isEditable: !presentation.isTextEditorDisabled && !configuration.isVoiceInteractionLocked,
            disabledCursor: configuration.isProjectTrustBlocked ? .operationNotAllowed : nil,
            imagePresentation: .textLinks,
            editorHorizontalInset: Self.editorHorizontalPadding,
            editorVerticalInset: Self.editorVerticalPadding,
            editorRoundedCorners: (configuration.hasQueuedMessages || hasAttachmentStrip) ? .bottom : .all,
            editorStrokedEdges: hasAttachmentStrip ? [.left, .bottom, .right] : .all,
            location: BlockInputComposerLocation(effectiveProjectDirectory: configuration.workingDirectory),
            urlOpener: configuration.urlOpener,
            localCommands: configuration.localCommands,
            passthroughSlashCommands: configuration.passthroughSlashCommands,
            loadFileCompletions: configuration.loadFileCompletions,
            loadSkillCompletions: configuration.loadSkillCompletions,
            keyboardShortcuts: blockInputKeyboardShortcuts(),
            completionPopupOverlayProvider: { [weak self] context in
                self?.blockInputCompletionPopupOverlay(context: context)
            },
            modalOverlayProvider: { [weak self] context in
                self?.blockInputModalOverlay(context: context)
            },
            onSelectionChange: { [weak self] selection in
                guard self?.latestSelection != selection else { return }
                self?.latestSelection = selection
                configuration.onVoiceInputAvailabilityChange()
            },
            onEditorInteractionUIChange: { _ in
                configuration.onVoiceInputAvailabilityChange()
            },
            onDocumentMutation: { [weak self] _, isEffectivelyEmpty in
                self?.configuration?.voiceEditorHandle?.recordDraftMutation()
                configuration.onVoiceInputAvailabilityChange()
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
            BlockInputKeyboardShortcut(key: .return, modifiers: .command): { [weak self] _ in
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
        guard !configuration.isVoiceInteractionLocked else {
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
        if configuration.onVoiceEscape() {
            return .handled
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

    func voiceInsertionContext() -> ComposerVoiceInsertionContext? {
        guard let bridgeController else {
            return nil
        }
        let document = bridgeController.documentStore.document
        let target: (BlockInputBlockID, NSRange)?
        switch latestSelection {
        case .cursor(let cursor):
            target = (cursor.blockID, NSRange(location: cursor.utf16Offset, length: 0))
        case .text(let selection):
            target = (selection.blockID, selection.range)
        case .blocks, .mixed:
            return nil
        case nil:
            let fallbackBlock = lastFocusedBlockID
                .flatMap { id in document.blocks.first(where: { $0.id == id }) }
                .flatMap { $0.kind.supportsVoiceInput ? $0 : nil }
                ?? document.blocks.last(where: { $0.kind.supportsVoiceInput })
            target = fallbackBlock.map { block in
                (block.id, NSRange(location: block.utf16Length, length: 0))
            }
        }
        guard let target,
              let block = document.blocks.first(where: { $0.id == target.0 }) else {
            return nil
        }
        return ComposerVoiceInsertionContext.capture(blockText: block.text, range: target.1)
    }
}
