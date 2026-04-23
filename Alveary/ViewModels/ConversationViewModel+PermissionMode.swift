import Foundation

extension ConversationViewModel {
    var effectivePermissionMode: String {
        state.runtimePermissionMode
            ?? dbConversation()?.thread?.permissionMode
            ?? "default"
    }

    func syncRuntimePermissionMode(_ permissionMode: String) {
        state.runtimePermissionMode = permissionMode
        if permissionMode != "plan" {
            state.lastNonPlanPermissionMode = permissionMode
        } else if state.lastNonPlanPermissionMode == nil,
                  let storedMode = dbConversation()?.thread?.permissionMode,
                  storedMode != "plan" {
            state.lastNonPlanPermissionMode = storedMode
        }

        guard let thread = dbThread(), thread.permissionMode != permissionMode else {
            return
        }

        thread.permissionMode = permissionMode
        do {
            try modelContext.save()
        } catch {
            // Best-effort: the live runtime state remains authoritative even if
            // the persisted picker state lags until the next successful save.
        }
    }
}
