import AgentCLIKit

/// Integrations withheld from every launch of a thread, persisted because the task kind that chose them is not
/// stored anywhere else — a relaunch, resume, or fork must not quietly hand the agent back what its creator withheld.
extension AgentThread {
    var integrationIsolation: AgentIntegrationIsolation {
        get { AgentIntegrationIsolation(rawValue: integrationIsolationRawValue) }
        set { integrationIsolationRawValue = newValue.rawValue }
    }
}
