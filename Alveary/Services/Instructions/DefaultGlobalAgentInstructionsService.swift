import Foundation

final class DefaultGlobalAgentInstructionsService: GlobalAgentInstructionsService, Sendable {
    static let sharedRelativePath = ".agents/AGENTS.md"

    private let agentRegistry: AgentRegistry
    private let homeDirectory: URL

    init(
        agentRegistry: AgentRegistry,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.agentRegistry = agentRegistry
        self.homeDirectory = homeDirectory
    }

    var sharedPathDescription: String {
        "~/\(Self.sharedRelativePath)"
    }

    func loadShared() async throws -> String {
        let sharedURL = sharedFileURL
        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: sharedURL.path) else {
                return ""
            }
            return try String(contentsOf: sharedURL, encoding: .utf8)
        }.value
    }

    func saveShared(_ markdown: String) async throws {
        let sharedURL = sharedFileURL
        try await Task.detached(priority: .utility) {
            try Self.writeShared(markdown, to: sharedURL)
        }.value
    }

    func linkStates() async -> [String: AgentInstructionsLinkState] {
        let paths = agentInstructionsURLs()
        let sharedURL = sharedFileURL
        return await Task.detached(priority: .utility) {
            paths.mapValues { Self.linkState(of: $0, sharedURL: sharedURL) }
        }.value
    }

    func copyIntoShared(agentID: String) async throws {
        let agentURL = try instructionsURL(forAgentID: agentID)
        let sharedURL = sharedFileURL
        let displayPath = try displayInstructionsPath(forAgentID: agentID)
        try await Task.detached(priority: .utility) {
            // Only a real per-agent file is copyable; reading through an already-linked
            // symlink would append the shared file's own content back into itself.
            guard case .hasOwnFile = Self.linkState(of: agentURL, sharedURL: sharedURL) else {
                return
            }
            let content = try String(contentsOf: agentURL, encoding: .utf8)
            try Self.appendToShared(content, from: displayPath, sharedURL: sharedURL)
        }.value
    }

    func link(agentID: String, copyingContents: Bool) async throws {
        let agentURL = try instructionsURL(forAgentID: agentID)
        let sharedURL = sharedFileURL
        let displayPath = try displayInstructionsPath(forAgentID: agentID)
        try await Task.detached(priority: .utility) {
            try Self.performLink(
                agentURL: agentURL,
                sharedURL: sharedURL,
                displayPath: displayPath,
                copyingContents: copyingContents
            )
        }.value
    }
}

private extension DefaultGlobalAgentInstructionsService {
    var sharedFileURL: URL {
        homeDirectory.appendingPathComponent(Self.sharedRelativePath)
    }

    func agentInstructionsURLs() -> [String: URL] {
        agentRegistry.agents.reduce(into: [:]) { urls, agent in
            guard let path = agent.instructionsPath else {
                return
            }
            urls[agent.id] = expandTilde(in: path)
        }
    }

    func instructionsURL(forAgentID agentID: String) throws -> URL {
        guard let agent = agentRegistry.agent(for: agentID) else {
            throw GlobalAgentInstructionsError.unknownAgent(agentID)
        }
        guard let path = agent.instructionsPath else {
            throw GlobalAgentInstructionsError.unsupportedAgent(agentID)
        }
        return expandTilde(in: path)
    }

    func displayInstructionsPath(forAgentID agentID: String) throws -> String {
        guard let path = agentRegistry.agent(for: agentID)?.instructionsPath else {
            throw GlobalAgentInstructionsError.unsupportedAgent(agentID)
        }
        return path
    }

    /// Expands a leading `~` against the injected home directory, not the process home,
    /// so tests can run against a temporary directory.
    func expandTilde(in path: String) -> URL {
        guard path == "~" || path.hasPrefix("~/") else {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: homeDirectory.path + String(path.dropFirst()))
    }

    static func linkState(of url: URL, sharedURL: URL) -> AgentInstructionsLinkState {
        let fileManager = FileManager.default
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            let resolvedDestination = resolvedPath(
                of: URL(
                    fileURLWithPath: destination,
                    relativeTo: url.deletingLastPathComponent()
                )
            )
            if resolvedDestination == resolvedPath(of: sharedURL) {
                return .linked
            }
            return .linkedElsewhere(target: resolvedDestination)
        }

        guard fileManager.fileExists(atPath: url.path) else {
            return .absent(path: url.path)
        }
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .absent(path: url.path)
        }
        return .hasOwnFile(path: url.path)
    }

    /// Resolves symlinks so a shared file that is itself a symlink still compares equal.
    /// Falls back to a standardized path when the target does not exist yet.
    static func resolvedPath(of url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func writeShared(_ markdown: String, to sharedURL: URL) throws {
        try FileManager.default.createDirectory(
            at: sharedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try markdown.write(to: sharedURL, atomically: true, encoding: .utf8)
    }

    static func appendToShared(_ content: String, from displayPath: String, sharedURL: URL) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let existing: String
        if FileManager.default.fileExists(atPath: sharedURL.path) {
            existing = try String(contentsOf: sharedURL, encoding: .utf8)
        } else {
            existing = ""
        }
        var merged = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if !merged.isEmpty {
            merged += "\n\n"
        }
        merged += "<!-- migrated from \(displayPath) -->\n\n\(trimmed)\n"
        try writeShared(merged, to: sharedURL)
    }

    static func performLink(
        agentURL: URL,
        sharedURL: URL,
        displayPath: String,
        copyingContents: Bool
    ) throws {
        switch linkState(of: agentURL, sharedURL: sharedURL) {
        case .linked:
            // Already linked to the shared file: nothing to migrate or back up.
            return
        case .linkedElsewhere:
            // The user pointed this path somewhere deliberate; never replace it.
            return
        case .hasOwnFile, .absent:
            break
        }

        let fileManager = FileManager.default

        // A dangling symlink would make both CLIs silently read nothing.
        if !fileManager.fileExists(atPath: sharedURL.path) {
            try writeShared("", to: sharedURL)
        }

        // Back up before any destructive step; a failed backup aborts the link.
        if fileManager.fileExists(atPath: agentURL.path) {
            let backupURL = agentURL.appendingPathExtension("backup")
            if copyingContents {
                let content = try String(contentsOf: agentURL, encoding: .utf8)
                try Self.appendToShared(content, from: displayPath, sharedURL: sharedURL)
            }
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: agentURL, to: backupURL)
            try fileManager.removeItem(at: agentURL)
        } else {
            try fileManager.createDirectory(
                at: agentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        try fileManager.createSymbolicLink(at: agentURL, withDestinationURL: sharedURL)
    }
}
