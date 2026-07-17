import SwiftUI

extension ChatView {
    var voiceInputModelModal: AppWindowModalOverlayPresenter.Modal? {
        guard voiceInputCoordinator.modelModalState != nil else {
            return nil
        }
        return AppWindowModalOverlayPresenter.Modal(
            id: "voice-input-model-preparation",
            dismissPolicy: .nonDismissible,
            content: AnyView(
                VoiceInputModelModalHost(
                    coordinator: voiceInputCoordinator,
                    onCancel: voiceInputCoordinator.cancelModelPreparationFromModal,
                    onContinue: voiceInputCoordinator.continueAfterModelPreparation,
                    onOpenMicrophoneSettings: {
                        openVoiceInputRecovery(.microphoneSettings)
                    }
                )
            )
        )
    }

    var chatWindowModal: AppWindowModalOverlayPresenter.Modal? {
        voiceInputModelModal ?? pausedQueueSendModal
    }

    func dismissChatWindowModal() {
        guard voiceInputModelModal == nil else {
            return
        }
        dismissPausedQueueSendConfirmation()
    }
}

private struct VoiceInputModelModalHost: View {
    let coordinator: ChatVoiceInputCoordinator
    let onCancel: () -> Void
    let onContinue: () -> Void
    let onOpenMicrophoneSettings: () -> Void

    var body: some View {
        if let state = coordinator.modelModalState {
            VoiceInputModelModal(
                state: state,
                onCancel: onCancel,
                onContinue: onContinue,
                onOpenMicrophoneSettings: onOpenMicrophoneSettings
            )
        }
    }
}

struct VoiceInputModelModalPresentation: Equatable {
    static let indeterminateProgressAccessibilityLabel = "Voice model preparation progress"

    private struct PreparationContent {
        let title: String
        let status: String
        let fraction: Double?
    }

    enum Indicator: Equatable {
        case progress(fraction: Double?)
        case success
        case failure
    }

    enum Action: Equatable {
        case cancel(isEnabled: Bool)
        case proceed
    }

    let title: String
    let status: String
    let indicator: Indicator
    let action: Action
    let showsMicrophoneSettings: Bool

    init(state: ChatVoiceInputModelModalState) {
        switch state {
        case .preparing(.ready), .ready:
            title = "Voice Input Is Ready"
            status = "The English voice model is loaded and ready for dictation."
            indicator = .success
            action = .proceed
            showsMicrophoneSettings = false
        case .preparing(let progress):
            let content = Self.preparationContent(progress)
            title = content.title
            status = content.status
            indicator = .progress(fraction: content.fraction)
            action = .cancel(isEnabled: true)
            showsMicrophoneSettings = false
        case .cancelling:
            title = "Cancelling Voice Model Setup"
            status = "Finishing local model cleanup. Resumable download data will be kept for the next attempt."
            indicator = .progress(fraction: nil)
            action = .cancel(isEnabled: false)
            showsMicrophoneSettings = false
        case .failed(let message, let recovery):
            title = "Voice Input Setup Failed"
            status = message
            indicator = .failure
            action = .cancel(isEnabled: true)
            showsMicrophoneSettings = recovery == .microphoneSettings
        }
    }

    private static func preparationContent(
        _ progress: VoiceInputPreparationProgress
    ) -> PreparationContent {
        switch progress {
        case .checkingPermission:
            return PreparationContent(
                title: "Preparing Voice Input",
                status: "Checking microphone access before preparing the local voice model…",
                fraction: nil
            )
        case .checkingModel:
            return PreparationContent(
                title: "Preparing Voice Input",
                status: "Checking the local voice model cache…",
                fraction: nil
            )
        case .downloading(let kind, let fraction):
            return downloadContent(kind: kind, fraction: fraction)
        case .loadingModel:
            return PreparationContent(
                title: "Loading Voice Model",
                status: "Loading the validated model for local transcription…",
                fraction: nil
            )
        case .ready:
            return PreparationContent(
                title: "Voice Input Is Ready",
                status: "The English voice model is loaded and ready for dictation.",
                fraction: 1
            )
        }
    }

    private static func downloadContent(
        kind: VoiceInputModelPreparationKind,
        fraction: Double?
    ) -> PreparationContent {
        switch kind {
        case .installation:
            return PreparationContent(
                title: "Downloading Voice Model",
                status: "Downloading the English voice model (about 600 MB)…",
                fraction: normalizedFraction(fraction)
            )
        case .update:
            return PreparationContent(
                title: "Updating Voice Model",
                status: "Updating the English voice model (about 600 MB)…",
                fraction: normalizedFraction(fraction)
            )
        case .repair:
            return PreparationContent(
                title: "Repairing Voice Model",
                status: "Repairing the English voice model (about 600 MB)…",
                fraction: normalizedFraction(fraction)
            )
        }
    }

    private static func normalizedFraction(_ fraction: Double?) -> Double? {
        guard let fraction, fraction.isFinite else {
            return nil
        }
        return min(max(fraction, 0), 1)
    }
}

struct VoiceInputModelModal: View {
    let state: ChatVoiceInputModelModalState
    let onCancel: () -> Void
    let onContinue: () -> Void
    let onOpenMicrophoneSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.46)
                    .ignoresSafeArea()

                panel(width: panelWidth(availableWidth: proxy.size.width))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(24)
            }
        }
        .zIndex(1_000)
    }

    private var presentation: VoiceInputModelModalPresentation {
        VoiceInputModelModalPresentation(state: state)
    }

    private func panel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(presentation.title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            indicator
                .padding(.top, 24)

            privacyExplanation
                .padding(.top, 24)

            actions
                .padding(.top, 24)
        }
        .padding(.top, 28)
        .padding(.horizontal, 30)
        .padding(.bottom, 28)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.34), radius: 28, x: 0, y: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice input model setup")
    }

    @ViewBuilder
    private var indicator: some View {
        switch presentation.indicator {
        case .progress(let fraction):
            VStack(alignment: .leading, spacing: 12) {
                Text(presentation.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let fraction {
                    ProgressView(value: fraction, total: 1)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Voice model download progress")
                        .accessibilityValue(Self.percentageText(fraction))
                    Text(Self.percentageText(fraction))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityHidden(true)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .accessibilityLabel(VoiceInputModelModalPresentation.indeterminateProgressAccessibilityLabel)
                }
            }
            .animation(reducesMotion ? nil : .easeOut(duration: 0.16), value: fraction)
        case .success:
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(presentation.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presentation.status)
        case .failure:
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(presentation.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presentation.status)
        }
    }

    private var privacyExplanation: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Voice input runs entirely on this Mac. Microphone audio is never uploaded or sent to any remote servers.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                Text("Only model files are downloaded. Dictated text stays in the composer until you choose to send it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if presentation.showsMicrophoneSettings {
                Button("Open Microphone Settings", action: onOpenMicrophoneSettings)
                    .secondaryActionButtonStyle()
            }
            Spacer(minLength: 0)
            switch presentation.action {
            case .cancel(let isEnabled):
                Button(isEnabled ? "Cancel" : "Cancelling…", action: onCancel)
                    .secondaryActionButtonStyle()
                    .disabled(!isEnabled)
            case .proceed:
                Button("Continue", action: onContinue)
                    .primaryActionButtonStyle()
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func panelWidth(availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth - 72, 360), 620)
    }

    private static func percentageText(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }
}
