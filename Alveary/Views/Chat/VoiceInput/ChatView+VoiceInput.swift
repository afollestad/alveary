@preconcurrency import AppKit

extension ChatView {
    var voiceInputComposerContext: ChatVoiceInputComposerContext {
        ChatVoiceInputComposerContext(
            draftIdentity: conversation.id,
            inputDraftRevision: viewModel.state.inputDraftRevision,
            attachmentIDs: stagedComposerAttachments.map(\.id),
            workingDirectory: workingDirectory
        )
    }

    var voiceInputShortcutAvailability: VoiceInputShortcutAvailability {
        _ = voiceShortcutRevalidationToken
        return settingsService?.current.voiceInputShortcutAvailability() ?? .unavailable(.notConfigured)
    }

    var voiceInputButtonConfiguration: ComposerVoiceInputConfiguration {
        let availability = voiceInputShortcutAvailability
        return ComposerVoiceInputConfiguration(
            phase: voiceInputCoordinator.phase,
            isEnabled: voiceInputCoordinator.isButtonEnabled && isVoiceInputActivationUsable,
            shortcutDisplay: availability.displayString,
            unavailableHelp: voiceInputButtonHelp(availability: availability),
            onPress: {
                voiceInputCoordinator.updateComposerContext(voiceInputComposerContext)
                return voiceInputCoordinator.physicalPress(.mouse)
            },
            onRelease: { forced in
                voiceInputCoordinator.physicalRelease(.mouse, forced: forced)
            },
            onAccessibilityToggle: {
                voiceInputCoordinator.updateComposerContext(voiceInputComposerContext)
                voiceInputCoordinator.accessibilityToggle()
            },
            onAccessibilityCancel: voiceInputCoordinator.cancelFromEscape
        )
    }

    var voiceInputShortcutConfiguration: AppKitVoiceInputShortcutConfiguration {
        let descriptor = voiceInputShortcutAvailability.descriptor
        return AppKitVoiceInputShortcutConfiguration(
            descriptor: descriptor,
            isEnabled: descriptor != nil && voiceInputCoordinator.isButtonEnabled && isVoiceInputActivationUsable,
            onEscape: voiceInputCoordinator.cancelFromEscape,
            onPress: {
                voiceInputCoordinator.updateComposerContext(voiceInputComposerContext)
                return voiceInputCoordinator.physicalPress(.keyboard)
            },
            onRelease: { forced in
                voiceInputCoordinator.physicalRelease(.keyboard, forced: forced)
            },
            onForcedStop: {
                voiceInputCoordinator.forceStopAndCommit(
                    reason: "Dictation stopped because the composer or app became inactive."
                )
            }
        )
    }

    var isBaseVoiceInputComposerUsable: Bool {
        _ = voiceSelectionRevalidationToken
        return composerInteractionOverlayID == nil &&
            !composerPresentation.isTextEditorDisabled &&
            !isProjectTrustBlocked &&
            voiceInputCoordinator.editorHandle.canStartVoiceInput
    }

    var isVoiceInputActivationUsable: Bool {
        isBaseVoiceInputComposerUsable || voiceInputCoordinator.phase == .recording
    }

    func voiceInputButtonHelp(availability: VoiceInputShortcutAvailability) -> String? {
        if !VoiceInputPlatform.isSupported {
            return VoiceInputShortcutUnavailableReason.unsupportedArchitecture.message
        }
        if voiceInputCoordinator.isVoiceInputOwnedElsewhere {
            return ChatVoiceInputCoordinator.voiceInputOwnedElsewhereMessage
        }
        if let reason = availability.unavailableReason,
           case .conflict = reason {
            return reason.message
        }
        return nil
    }

    func openVoiceInputRecovery(_ recovery: ChatVoiceInputNotice.Recovery) {
        switch recovery {
        case .microphoneSettings:
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }
}
