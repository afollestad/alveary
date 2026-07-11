import AppKit
import Foundation

extension ChatView {
    #if DEBUG
    func copyAppShotDebugPreview() {
        let draft = viewModel.flushDraftFromEditor()
        do {
            guard !viewModel.state.stagedAppShots.isEmpty else {
                throw AgentError.spawnFailed("No staged app shots to preview.")
            }
            let preview = try viewModel.appShotDebugPreview(providerID: providerID, userInput: draft.messageText)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(preview, forType: .string)
        } catch {
            viewModel.lastTurnError = error.localizedDescription
        }
    }
    #endif
}
