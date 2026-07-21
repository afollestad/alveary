import Foundation
import Observation

enum MCPPaneTarget: Hashable {
    case addCustom
    case addRecommended(String)
    case edit(String)

    var defaultFocusRestorationID: String {
        switch self {
        case .addCustom:
            "mcp-add"
        case .addRecommended(let serverID):
            "mcp-recommended-\(serverID)"
        case .edit(let serverName):
            "mcp-edit-\(serverName)"
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
    var draft: MCPServerDraft
    var errorMessage: String?
    var isSubmitting = false
}

@MainActor
@Observable
final class MCPViewModel {
    private let mcpService: any MCPService

    private(set) var servers: [MCPServer] = []
    private(set) var recommended: [RecommendedMCPServer] = []
    private(set) var availableAgents: [MCPAgentAvailability] = []
    private(set) var activePaneTarget: MCPPaneTarget?
    private(set) var paneSessions: [MCPPaneTarget: MCPPaneSession] = [:]
    private(set) var pendingPaneDismissals: Set<PaneSessionDismissalRequest<MCPPaneTarget>> = []
    private(set) var paneDismissalGeneration = 0
    private(set) var paneFocusRestorationID = MCPPaneTarget.addCustom.defaultFocusRestorationID
    private var deactivatedPaneDismissals: Set<PaneSessionDismissalRequest<MCPPaneTarget>> = []
    var searchQuery: String = ""

    init(mcpService: any MCPService) {
        self.mcpService = mcpService
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
              !session.isSubmitting else {
            return
        }
        let generation = session.generation
        session.isSubmitting = true
        session.errorMessage = nil
        paneSessions[target] = session

        do {
            try await addServer(session.draft.makeServer(), for: Array(session.draft.selectedAgents))
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
    func activate(_ target: MCPPaneTarget, makeDraft: () -> MCPServerDraft) {
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
