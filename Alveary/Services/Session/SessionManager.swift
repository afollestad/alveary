import Foundation

struct SessionEntry: Codable, Sendable, Equatable {
    var cwd: String
    var harnessId: String
    var appSessionId: String
    var launchSessionId: String

    /// Keep the stored JSON format stable across the harness terminology rename.
    private enum CodingKeys: String, CodingKey {
        case cwd
        case harnessId = "providerId"
        case appSessionId
        case launchSessionId
    }
}

protocol SessionManager: Actor {
    func createEntry(conversationId: String, cwd: String, harnessId: String) -> Bool
    func removeEntry(for conversationId: String) throws
    func hasSession(for conversationId: String) -> Bool
    func sessionId(for conversationId: String) -> String
    func conversationId(forSessionId sessionId: String, cwd: String, harnessId: String) -> String?
    func updateSessionId(for conversationId: String, newSessionId: String) throws
    func load()
    // Orderly shutdown bridges this async persist through a detached task while the main thread
    // is synchronously blocked in `applicationWillTerminate`, so implementations must stay off
    // `@MainActor`.
    func persist() throws
}
