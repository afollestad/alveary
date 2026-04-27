import SwiftUI

extension ChatTranscriptView {
    func retryAction(
        for id: String,
        isRetryable: Bool
    ) -> (() -> Void)? {
        guard isRetryable else {
            return nil
        }
        return {
            Task {
                do {
                    try await viewModel.retryFailedUserMessage(id: id)
                } catch {
                    if viewModel.lastTurnError == nil {
                        viewModel.lastTurnError = error.localizedDescription
                    }
                }
            }
        }
    }
}
