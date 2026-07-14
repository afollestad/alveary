import AgentCLIKit
import Foundation

extension AgentCLIKitEventMapper {
    func diagnosticEvents(from event: AgentCLIKit.AgentDiagnosticEvent) -> [ConversationEvent] {
        if event.code == .hostToolServerUnavailable {
            return []
        }
        if event.code == .hookApprovalFailed {
            return [.toolApprovalFailed(ToolApprovalFailure(
                sessionId: event.metadata.diagnosticStringValue("session_id"),
                toolUseId: event.metadata.diagnosticStringValue("tool_use_id"),
                toolName: event.metadata.diagnosticStringValue("tool_name"),
                message: event.message
            ))]
        }
        if event.code == .codexAppServerResponseFailure,
           event.severity == .warning,
           event.metadata.diagnosticStringValue("codex_status")?.lowercased() == "systemerror" {
            return [.error(message: event.message)]
        }
        if event.severity == .error {
            return [.error(message: event.message)]
        }
        guard event.message == "init",
              let sessionId = event.metadata.diagnosticStringValue("session_id") else {
            return []
        }
        return [.sessionInit(sessionId: sessionId)]
    }
}

private extension [String: AgentCLIKit.JSONValue] {
    func diagnosticStringValue(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else {
            return nil
        }
        return value
    }
}
