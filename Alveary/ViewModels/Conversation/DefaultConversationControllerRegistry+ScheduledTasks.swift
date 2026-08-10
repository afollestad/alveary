import Foundation

extension DefaultConversationControllerRegistry {
    func currentOutcome(for key: ConversationControllerKey) -> ConversationControllerOutcome? {
        outcomeHubs[key]?.current
    }

    func isReadyForScheduledTask(conversationID: String) -> Bool {
        controllersAreReadyForScheduledTask(
            conversationID: conversationID,
            requiresDurableRunFence: true
        )
    }

    func isReadyForScheduledTaskRecovery(conversationID: String) -> Bool {
        controllersAreReadyForScheduledTask(
            conversationID: conversationID,
            requiresDurableRunFence: false
        )
    }

    private func controllersAreReadyForScheduledTask(
        conversationID: String,
        requiresDurableRunFence: Bool
    ) -> Bool {
        let targetThreadID = entries.values.lazy.compactMap { entry in
            entry.viewModel.dbThread().flatMap { thread in
                thread.conversations.contains(where: { $0.id == conversationID })
                    ? thread.persistentModelID
                    : nil
            }
        }.first
        guard let targetThreadID else {
            return true
        }

        return entries.values.filter { entry in
            entry.viewModel.dbThread()?.persistentModelID == targetThreadID
        }.allSatisfy { entry in
            (!requiresDurableRunFence || !entry.viewModel.defersOrdinaryScheduledOutbound) &&
                entry.viewModel.isReadyForExistingScheduledTask &&
                entry.controllerPhase == .idle &&
                !entry.hasActiveWork &&
                entry.pendingTerminals.isEmpty &&
                entry.terminalMaintenanceTask == nil
        }
    }
}
