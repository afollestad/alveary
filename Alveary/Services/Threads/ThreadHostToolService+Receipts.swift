import Foundation
import SwiftData

/// The exact-retry ledger `create_thread` and `send_prompt_to_thread` share. Both apply on the
/// first call, so a provider retransmitting the same request must get the recorded answer back
/// rather than a second thread or a second copy of the prompt.
extension ThreadHostToolService {
    func replayedReceipt(
        on sourceConversation: Conversation,
        deduplicationKey: String,
        processToken: UUID,
        at requestDate: Date
    ) throws -> ThreadHostToolReceipt? {
        do {
            let receipt = try sourceConversation.threadHostToolReceipt(
                matching: deduplicationKey,
                currentProcessToken: processToken,
                at: requestDate
            )
            if modelContext.hasChanges {
                try modelContext.save()
            }
            return receipt
        } catch {
            modelContext.rollback()
            throw ThreadHostToolServiceError.persistenceFailure
        }
    }

    /// Its own save, separate from whatever the call applied: a failed ledger write must not roll
    /// back a thread the user can already see or a prompt already on its way.
    func persistReceipt(
        _ receipt: ThreadHostToolReceipt,
        on sourceConversation: Conversation
    ) throws {
        do {
            try sourceConversation.recordThreadHostToolReceipt(receipt)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw ThreadHostToolServiceError.persistenceFailure
        }
    }
}
