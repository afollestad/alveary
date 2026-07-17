import AppKit

extension ChatComposerActionRowView {
    func setupAccessoryViews() {
        contextIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        contextIndicatorView.setContentHuggingPriority(.required, for: .horizontal)
    }

    func applyAccessoryConfiguration(_ configuration: Configuration) {
        contextIndicatorView.configure(summary: configuration.usageSummary)
    }

    func applyVoiceInputConfiguration(_ configuration: Configuration) {
        guard let voiceInput = configuration.voiceInput else {
            return
        }
        voiceInputButton.configure(voiceInput)
    }

    func voiceInputViews(_ configuration: Configuration) -> [NSView] {
        configuration.voiceInput == nil ? [] : [voiceInputButton]
    }

    func forceVoiceInputMouseRelease() {
        voiceInputButton.forceMouseRelease()
    }
}
