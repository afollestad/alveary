import BlockInputKit
import Foundation

struct ComposerDraft: Equatable, Sendable {
    let text: String
    let source: ComposerDraftSource
    private let cachedIsEffectivelyEmpty: Bool?

    init(
        text: String,
        source: ComposerDraftSource,
        isEffectivelyEmpty: Bool? = nil
    ) {
        self.text = text
        self.source = source
        cachedIsEffectivelyEmpty = isEffectivelyEmpty
    }

    var isEffectivelyEmpty: Bool {
        if let cachedIsEffectivelyEmpty {
            return cachedIsEffectivelyEmpty
        }

        switch source {
        case .legacyText:
            return ChatInputFieldTextSupport.isEffectivelyEmpty(text)
        case .blockInputMarkdown:
            return BlockInputDocument(markdown: text).isEffectivelyEmpty
        }
    }

    func outboundMessage(workingDirectory: String?) -> String {
        switch source {
        case .legacyText:
            ChatInputFieldTextSupport.outboundMessage(from: text, workingDirectory: workingDirectory)
        case .blockInputMarkdown:
            text
        }
    }
}

@MainActor
extension ConversationViewModel {
    func flushDraftFromEditor() -> ComposerDraft {
        ComposerDraft(
            text: state.inputDraft,
            source: state.inputDraftSource,
            isEffectivelyEmpty: state.inputDraftIsEffectivelyEmpty
        )
    }

    func publishComposerDraft(_ text: String, source: ComposerDraftSource) {
        setInputDraft(text, source: source, advancesRevision: false)
    }

    func recordBlockInputDraftMutation(isEffectivelyEmpty: Bool) {
        state.inputDraftPublishTask?.cancel()
        state.inputDraftPublishTask = nil
        state.inputDraftSource = .blockInputMarkdown
        state.inputDraftDirtyRevision += 1
        state.inputDraftIsEffectivelyEmpty = isEffectivelyEmpty
        cancelSessionHandoffSteeringCountdownForEditorMutation()
        cancelSessionHandoffCountdownForEditorMutation()
    }

    func scheduleBlockInputDraftPublish(
        _ document: BlockInputDocument,
        delay: Duration = .milliseconds(25)
    ) {
        let dirtyRevision = state.inputDraftDirtyRevision
        state.inputDraftPublishTask?.cancel()
        state.inputDraftPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  let self,
                  self.state.inputDraftDirtyRevision == dirtyRevision else {
                return
            }

            let markdown = document.markdown
            self.setInputDraft(
                markdown,
                source: .blockInputMarkdown,
                isEffectivelyEmpty: document.isEffectivelyEmpty,
                cancelsPendingBlockInputPublish: false,
                advancesRevision: false
            )
            self.cancelSessionHandoffSteeringCountdownIfDraftChanged(to: markdown)
            self.cancelSessionHandoffCountdownIfDraftChanged(to: markdown)
            self.state.inputDraftPublishTask = nil
        }
    }

    func replaceInputDraft(_ text: String, source: ComposerDraftSource? = nil) {
        setInputDraft(text, source: source ?? state.inputDraftSource)
    }

    func clearInputDraft(source: ComposerDraftSource? = nil) {
        setInputDraft("", source: source ?? state.inputDraftSource)
    }

    func appendToInputDraft(_ text: String, source: ComposerDraftSource? = nil) {
        let draft = flushDraftFromEditor()
        let nextText = draft.text.isEmpty ? text : draft.text + "\n\n" + text
        setInputDraft(nextText, source: source ?? draft.source)
    }

    private func cancelSessionHandoffSteeringCountdownForEditorMutation() {
        guard state.isAwaitingHandoffSteering,
              state.handoffSteeringCountdownRemaining != nil else {
            return
        }

        cancelSessionHandoffSteeringCountdown()
    }

    private func setInputDraft(
        _ text: String,
        source: ComposerDraftSource,
        isEffectivelyEmpty: Bool? = nil,
        cancelsPendingBlockInputPublish: Bool = true,
        advancesRevision: Bool = true
    ) {
        if cancelsPendingBlockInputPublish {
            state.inputDraftPublishTask?.cancel()
            state.inputDraftPublishTask = nil
        }

        let nextIsEffectivelyEmpty = isEffectivelyEmpty ?? ComposerDraft(
            text: text,
            source: source
        ).isEffectivelyEmpty

        guard state.inputDraft != text ||
            state.inputDraftSource != source ||
            state.inputDraftIsEffectivelyEmpty != nextIsEffectivelyEmpty else {
            return
        }

        state.inputDraft = text
        state.inputDraftSource = source
        state.inputDraftIsEffectivelyEmpty = nextIsEffectivelyEmpty
        if advancesRevision {
            // The BlockInput bridge consumes this revision only for app-owned replacements.
            state.inputDraftRevision += 1
        }
    }
}
