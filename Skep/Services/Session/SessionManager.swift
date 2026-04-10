import Foundation

struct SessionEntry: Codable, Sendable, Equatable {
    var cwd: String
    var providerId: String
    var appSessionId: String
    var launchSessionId: String
}

protocol SessionManager: Actor {
    func createEntry(conversationId: String, cwd: String, providerId: String) -> Bool
    func removeEntry(for conversationId: String) throws
    func hasSession(for conversationId: String) -> Bool
    func sessionId(for conversationId: String) -> String
    func conversationId(forSessionId sessionId: String, cwd: String, providerId: String) -> String?
    func updateSessionId(for conversationId: String, newSessionId: String) throws
    func load()
    func persist() throws
}
