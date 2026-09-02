import AgentCLIKit
import Foundation

/// One enrolled feature's `alveary_host` tools as the MCP screen's Built-in section lists
/// them: a card per feature rather than per tool, because the full catalog runs to dozens
/// of tools and a row each pushed the user's own servers off the first screen.
///
/// Read-only by design. The section shows these beside the servers the user configures so
/// the tools are discoverable, but nothing here can be edited or removed, so this carries no
/// draft and no mutation path — which is also why it is a value derived from the static
/// catalog rather than something `MCPService` loads.
struct BuiltInMCPToolGroup: Identifiable, Equatable, Sendable {
    /// The feature's `HostToolFeatureCatalog.featureID`, such as `threads`.
    let id: String
    /// The feature's `HostToolFeatureCatalog.title`, such as `Threads`.
    let title: String
    let tools: [BuiltInMCPTool]

    /// Every enrolled feature in enrollment order, each with its tools in catalog order.
    /// Iterates the feature catalogs rather than `AlvearyHostToolCatalog.tools` to keep the
    /// grouping; `BuiltInMCPToolGroupTests` holds the flattened names to the same list.
    static var all: [BuiltInMCPToolGroup] {
        AlvearyHostToolCatalog.featureCatalogs.map { catalog in
            BuiltInMCPToolGroup(
                id: catalog.featureID,
                title: catalog.title,
                tools: catalog.tools.map(BuiltInMCPTool.init)
            )
        }
    }
}

/// The user-facing projection of one catalog definition, without its schemas.
struct BuiltInMCPTool: Identifiable, Equatable, Sendable {
    var id: String { name }

    /// Bare host tool name, such as `list_threads`. Claude reports it prefixed instead —
    /// see `AlvearyHostToolCatalog.qualifiedToolName`.
    let name: String
    let title: String
    let description: String
    /// Whether the tool only reads Alveary state, from the definition's MCP annotations.
    let isReadOnly: Bool

    init(name: String, title: String, description: String, isReadOnly: Bool) {
        self.name = name
        self.title = title
        self.description = description
        self.isReadOnly = isReadOnly
    }

    init(_ definition: AgentCLIKit.AgentHostToolDefinition) {
        self.init(
            name: definition.name,
            title: definition.title ?? definition.name,
            description: definition.description,
            isReadOnly: definition.annotations.readOnlyHint == true
        )
    }
}
