import Foundation
import Observation

enum MCPPaneTarget: Hashable {
    case addCustom
    case addRecommended(String)
    case edit(String)
    /// Read-only details for one feature's `alveary_host` tools, keyed by
    /// `BuiltInMCPToolGroup.id`.
    case builtInToolGroup(String)

    var defaultFocusRestorationID: String {
        switch self {
        case .addCustom:
            "mcp-add"
        case .addRecommended(let serverID):
            "mcp-recommended-\(serverID)"
        case .edit(let serverName):
            "mcp-edit-\(serverName)"
        case .builtInToolGroup(let groupID):
            "mcp-built-in-\(groupID)"
        }
    }
}

struct MCPServerDraft: Equatable {
    var name: String
    var transport: MCPServer.Transport
    var command: String
    var argsText: String
    var url: String
    var headersText: String
    var envText: String
    var selectedAgents: Set<String>

    init(availableAgents: [MCPAgentAvailability]) {
        name = ""
        transport = .stdio
        command = ""
        argsText = ""
        url = ""
        headersText = ""
        envText = ""
        selectedAgents = Set(availableAgents.map(\.agentId))
    }

    init(server: MCPServer) {
        name = server.name
        transport = server.transport
        command = server.command ?? ""
        argsText = server.args?.joined(separator: " ") ?? ""
        url = server.url ?? ""
        headersText = Self.serialize(dictionary: server.headers)
        envText = Self.serialize(dictionary: server.env)
        selectedAgents = Set(server.providers)
    }

    init(recommended: RecommendedMCPServer, availableAgents: [MCPAgentAvailability]) {
        self.init(server: recommended.template)
        if !recommended.headerPrompts.isEmpty {
            headersText = recommended.headerPrompts.map { "\($0)=" }.joined(separator: "\n")
        }
        selectedAgents = Set(availableAgents.filter {
            $0.supportedTransports.contains(recommended.template.transport)
        }.map(\.agentId))
    }

    func makeServer() -> MCPServer {
        let parsedArgs = argsText.split(whereSeparator: \.isWhitespace).map(String.init)

        return MCPServer(
            name: name,
            transport: transport,
            command: command.isEmpty ? nil : command,
            args: parsedArgs.isEmpty ? nil : parsedArgs,
            url: url.isEmpty ? nil : url,
            headers: Self.parse(lines: headersText),
            env: Self.parse(lines: envText),
            providers: Array(selectedAgents).sorted()
        )
    }

    private static func parse(lines: String) -> [String: String]? {
        let pairs = lines
            .split(separator: "\n")
            .compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard let key = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !key.isEmpty else {
                    return nil
                }
                let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                return (key, value)
            }

        guard !pairs.isEmpty else {
            return nil
        }
        return Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
    }

    private static func serialize(dictionary: [String: String]?) -> String {
        dictionary?
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n") ?? ""
    }
}

struct MCPPaneSession: Equatable {
    let generation: UUID
    /// `nil` for a built-in tool group's details, which have nothing to edit and nothing
    /// to submit; the session then exists only to give the pane a presentation generation.
    var draft: MCPServerDraft?
    var errorMessage: String?
    var isSubmitting = false
}

@MainActor
@Observable
final class MCPViewModel {
    private let mcpService: any MCPService

    /// Where the grid was scrolled to, so leaving the screen and coming back lands there; see
    /// ``ScrollOffsetStore`` for why it cannot live on the screen.
    @ObservationIgnored let listScrollOffset = ScrollOffsetStore()

    /// The `alveary_host` tools the screen lists read-only above the user's servers, one
    /// group per feature. Static for the app's lifetime, so `load()` never touches it;
    /// injected so snapshots can keep the previews short.
    let builtInToolGroups: [BuiltInMCPToolGroup]

    private(set) var servers: [MCPServer] = []
    private(set) var recommended: [RecommendedMCPServer] = []
    private(set) var availableAgents: [MCPAgentAvailability] = []
    private(set) var activePaneTarget: MCPPaneTarget?
    private(set) var paneSessions: [MCPPaneTarget: MCPPaneSession] = [:]
    private(set) var pendingPaneDismissals: Set<PaneSessionDismissalRequest<MCPPaneTarget>> = []
    private(set) var isRefreshingProviders = false
    private(set) var paneDismissalGeneration = 0
    private(set) var paneFocusRestorationID = MCPPaneTarget.addCustom.defaultFocusRestorationID
    private var deactivatedPaneDismissals: Set<PaneSessionDismissalRequest<MCPPaneTarget>> = []
    var searchQuery: String = ""

    init(
        mcpService: any MCPService,
        builtInToolGroups: [BuiltInMCPToolGroup] = BuiltInMCPToolGroup.all
    ) {
        self.mcpService = mcpService
        self.builtInToolGroups = builtInToolGroups
    }

    /// A query matching a group's title keeps the whole group; otherwise the group is
    /// narrowed to the tools that match, so its card previews exactly what was found.
    var filteredBuiltInToolGroups: [BuiltInMCPToolGroup] {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            return builtInToolGroups
        }

        return builtInToolGroups.compactMap { group in
            if group.title.localizedCaseInsensitiveContains(query) {
                return group
            }
            let tools = group.tools.filter { tool in
                tool.name.localizedCaseInsensitiveContains(query) ||
                    tool.title.localizedCaseInsensitiveContains(query) ||
                    tool.description.localizedCaseInsensitiveContains(query)
            }
            guard !tools.isEmpty else {
                return nil
            }
            return BuiltInMCPToolGroup(id: group.id, title: group.title, tools: tools)
        }
    }

    /// The unfiltered group, which is what its pane lists even while a search narrows the card.
    func builtInToolGroup(id: String) -> BuiltInMCPToolGroup? {
        builtInToolGroups.first { $0.id == id }
    }

    var filteredServers: [MCPServer] {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            return servers
        }

        return servers.filter { server in
            server.name.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredRecommended: [RecommendedMCPServer] {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            return recommended
        }

        return recommended.filter { entry in
            entry.template.name.localizedCaseInsensitiveContains(query) ||
                entry.description.localizedCaseInsensitiveContains(query) ||
                entry.headerPrompts.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    func load() async {
        servers = (try? await mcpService.loadAll()) ?? []
        recommended = (try? await mcpService.loadRecommended()) ?? []
        availableAgents = await mcpService.availableAgents()
    }

    func addServer(_ server: MCPServer, for agents: [String]) async throws {
        try await mcpService.addServer(server, for: agents)
        await load()
    }

    func removeServer(_ server: MCPServer) async throws {
        try await mcpService.removeServer(server)
        await load()
        let target = MCPPaneTarget.edit(server.name)
        if let generation = paneSessions[target]?.generation {
            if activePaneTarget == target {
                paneFocusRestorationID = MCPPaneTarget.addCustom.defaultFocusRestorationID
            }
            pendingPaneDismissals.insert(.init(target: target, generation: generation))
        }
    }

    func refreshProviders() async {
        guard !isRefreshingProviders else {
            return
        }
        isRefreshingProviders = true
        defer {
            isRefreshingProviders = false
        }
        await load()
    }

    func requestAddCustom(focusRestorationID: String? = nil) {
        paneFocusRestorationID = focusRestorationID ?? MCPPaneTarget.addCustom.defaultFocusRestorationID
        activate(.addCustom) {
            MCPServerDraft(availableAgents: availableAgents)
        }
    }

    func requestAddRecommended(_ recommended: RecommendedMCPServer, focusRestorationID: String? = nil) {
        let target = MCPPaneTarget.addRecommended(recommended.id)
        paneFocusRestorationID = focusRestorationID ?? target.defaultFocusRestorationID
        activate(target) {
            MCPServerDraft(recommended: recommended, availableAgents: availableAgents)
        }
    }

    func requestEdit(_ server: MCPServer, focusRestorationID: String? = nil) {
        let target = MCPPaneTarget.edit(server.name)
        paneFocusRestorationID = focusRestorationID ?? target.defaultFocusRestorationID
        activate(target) {
            MCPServerDraft(server: server)
        }
    }

    func requestBuiltInToolGroupDetails(_ group: BuiltInMCPToolGroup, focusRestorationID: String? = nil) {
        let target = MCPPaneTarget.builtInToolGroup(group.id)
        paneFocusRestorationID = focusRestorationID ?? target.defaultFocusRestorationID
        activate(target) {
            nil
        }
    }

    func updateActiveDraft(_ draft: MCPServerDraft) {
        guard let target = activePaneTarget,
              var session = paneSessions[target] else {
            return
        }
        session.draft = draft
        session.errorMessage = nil
        paneSessions[target] = session
    }

    func clearActivePaneError() {
        guard let target = activePaneTarget else {
            return
        }
        paneSessions[target]?.errorMessage = nil
    }

    func submitActivePane() async {
        guard let target = activePaneTarget,
              var session = paneSessions[target],
              let draft = session.draft,
              !session.isSubmitting else {
            return
        }
        let generation = session.generation
        session.isSubmitting = true
        session.errorMessage = nil
        paneSessions[target] = session

        do {
            try await addServer(draft.makeServer(), for: Array(draft.selectedAgents))
            guard paneSessions[target]?.generation == generation else {
                return
            }
            if activePaneTarget == target {
                switch target {
                case .addCustom, .addRecommended:
                    paneFocusRestorationID = MCPPaneTarget.addCustom.defaultFocusRestorationID
                case .edit(let originalName):
                    if !filteredServers.contains(where: { $0.name == originalName }) {
                        paneFocusRestorationID = MCPPaneTarget.addCustom.defaultFocusRestorationID
                    }
                case .builtInToolGroup:
                    // Unreachable: a built-in group's session has no draft, so the guard
                    // above already returned.
                    break
                }
            }
            pendingPaneDismissals.insert(.init(target: target, generation: generation))
        } catch {
            guard var liveSession = paneSessions[target],
                  liveSession.generation == generation else {
                return
            }
            liveSession.isSubmitting = false
            liveSession.errorMessage = error.localizedDescription
            paneSessions[target] = liveSession
        }
    }

    func deactivatePane() {
        activePaneTarget = nil
    }

    func deactivatePane(_ target: MCPPaneTarget, generation: UUID) {
        guard activePaneTarget == target,
              paneSessions[target]?.generation == generation else {
            return
        }
        let request = PaneSessionDismissalRequest(target: target, generation: generation)
        pendingPaneDismissals.insert(request)
        deactivatedPaneDismissals.insert(request)
        activePaneTarget = nil
    }

    func dismissActivePane() {
        guard let target = activePaneTarget,
              let generation = paneSessions[target]?.generation else {
            return
        }
        dismissPane(target, generation: generation)
    }

    func dismissPane(
        _ target: MCPPaneTarget,
        generation: UUID,
        restoreFocus: Bool = true
    ) {
        let request = PaneSessionDismissalRequest(target: target, generation: generation)
        guard paneSessions[target]?.generation == generation else {
            pendingPaneDismissals.remove(request)
            deactivatedPaneDismissals.remove(request)
            return
        }
        pendingPaneDismissals.remove(request)
        let ownedDeactivation = deactivatedPaneDismissals.remove(request) != nil
        let shouldRestoreFocus = activePaneTarget == target || (ownedDeactivation && activePaneTarget == nil)
        discardSession(for: target)
        if restoreFocus, shouldRestoreFocus {
            paneDismissalGeneration &+= 1
        }
    }
}

private extension MCPViewModel {
    func activate(_ target: MCPPaneTarget, makeDraft: () -> MCPServerDraft?) {
        if let request = pendingPaneDismissals.first(where: { $0.target == target }) {
            deactivatedPaneDismissals.remove(request)
            dismissPane(target, generation: request.generation, restoreFocus: false)
        }
        if paneSessions[target] == nil {
            paneSessions[target] = MCPPaneSession(generation: UUID(), draft: makeDraft())
        }
        if let generation = paneSessions[target]?.generation {
            deactivatedPaneDismissals.remove(.init(target: target, generation: generation))
        }
        activePaneTarget = target
    }

    func discardSession(for target: MCPPaneTarget) {
        paneSessions.removeValue(forKey: target)
        if activePaneTarget == target {
            activePaneTarget = nil
        }
    }

    var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
