import AgentCLIKit
import Foundation

/// What one Alveary feature advertises on the shared `alveary_host` MCP server.
///
/// Definitions are consumed statically when a turn spawns, so they must not require any
/// service instance; handling is separate and lives on `HostToolFeature`.
struct HostToolFeatureCatalog: Sendable {
    /// Stable identifier used in diagnostics and collision reports, such as `scheduling`.
    let featureID: String
    /// What the MCP screen's Built-in section calls this feature's tools, such as `Threads`;
    /// sentence case, matching the sidebar.
    let title: String
    let tools: [AgentCLIKit.AgentHostToolDefinition]
    /// The feature's paragraph of server instructions, composed into one blob by
    /// `AlvearyHostToolCatalog` in enrollment order.
    let instructionsFragment: String

    var toolNames: [String] {
        tools.map(\.name)
    }
}

/// A feature that handles calls for the tools it advertises.
///
/// `HostToolDispatcher` routes by tool name, so `hostToolNames` must exactly cover the
/// feature catalog's tools; `AlvearyHostToolCatalogTests` asserts that parity.
@MainActor
protocol HostToolFeature: AnyObject {
    var featureID: String { get }
    var hostToolNames: Set<String> { get }

    func handle(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) async -> AgentCLIKit.AgentHostToolResult
}
