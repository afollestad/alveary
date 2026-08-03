import AgentCLIKit
import Foundation

/// The one MCP server Alveary exposes to provider processes, composed from per-feature catalogs.
///
/// AgentCLIKit registers a single server per process, so every Alveary feature shares this
/// identity, this instructions blob, and `HostToolDispatcher`'s name routing. Enroll a feature
/// by appending its `HostToolFeatureCatalog` to `featureCatalogs` and its handler to the
/// dispatcher in `AppComponent+HostMCP.swift`.
enum AlvearyHostToolCatalog {
    /// Provider-facing MCP server name. The single owner of this string.
    static let serverName = "alveary_host"

    /// The name Claude reports for a host tool; Codex reports the bare host name instead.
    static func qualifiedToolName(_ hostToolName: String) -> String {
        "mcp__\(serverName)__\(hostToolName)"
    }

    /// Providers disagree on whether a reported tool name carries the server prefix, and both
    /// shapes reach the transcript, so name matching has to answer to either.
    static func matches(reportedName: String, hostToolName: String) -> Bool {
        reportedName == hostToolName || reportedName == qualifiedToolName(hostToolName)
    }

    /// Enrollment order, which is also the order feature instructions appear in.
    static var featureCatalogs: [HostToolFeatureCatalog] {
        [ScheduledTaskHostToolCatalog.featureCatalog]
    }

    static var serverMetadata: AgentCLIKit.AgentHostToolServerMetadata {
        AgentCLIKit.AgentHostToolServerMetadata(
            name: serverName,
            title: "Alveary",
            instructions: instructions
        )
    }

    static var tools: [AgentCLIKit.AgentHostToolDefinition] {
        let catalogs = featureCatalogs
        if let collision = HostToolDispatcher.duplicateToolName(in: catalogs.map { Set($0.toolNames) }) {
            preconditionFailure("Duplicate alveary_host tool name across feature catalogs: \(collision)")
        }
        return catalogs.flatMap(\.tools)
    }

    static var instructions: String {
        ([instructionsPreamble] + featureCatalogs.map(\.instructionsFragment))
            .joined(separator: "\n\n")
    }

    static let instructionsPreamble = """
    These tools act on Alveary itself, the macOS app hosting this conversation; they do not touch the user's code or files. \
    Use each one only for the purpose its own description states, and only when the user explicitly asks for it. \
    Never substitute shell commands, config files, or the file system for one of these tools, and never invent a tool this \
    server does not list. If a tool is unavailable or fails, say so and point the user at the matching Alveary screen instead \
    of attempting a workaround.
    """
}
