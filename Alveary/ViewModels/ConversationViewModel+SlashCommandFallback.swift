import Foundation

struct TokenEventPayload {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreation: Int
    let isError: Bool
    let stopReason: String?
    let permissionDenials: [PermissionDenialSummary]
}

enum TokenEventPersistence {
    case persistTokens
    case dropTokens
    case persistSyntheticStop(message: String)
    case persistSyntheticAssistant(message: String)
}

extension ConversationState {
    func synthesizedSlashCommandFailureNotice(
        for payload: TokenEventPayload,
        hadStreamingText: Bool? = nil
    ) -> String? {
        let sawStreamingText = hadStreamingText ?? (streamingText != nil)

        guard !payload.isError,
              payload.permissionDenials.isEmpty,
              !sawStreamingText,
              payload.input == 0,
              payload.output == 0,
              payload.cacheRead == 0,
              payload.cacheCreation == 0,
              payload.stopReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let slashCommand = latestSlashCommandCandidate() else {
            return nil
        }

        return "Unknown command: \(slashCommand)"
    }

    func latestSlashCommandCandidate() -> String? {
        guard let lastItem = grouper.items.last,
              case .userMessage(_, let text) = lastItem else {
            return nil
        }

        let slashCommand = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard slashCommand.hasPrefix("/") else {
            return nil
        }

        return slashCommand
    }
}
