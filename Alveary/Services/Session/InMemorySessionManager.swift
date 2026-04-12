import Foundation

actor InMemorySessionManager: SessionManager {
    private var entries: [String: SessionEntry] = [:]

    func createEntry(conversationId: String, cwd: String, providerId: String) -> Bool {
        let normalizedCWD = CanonicalPath.normalize(cwd)
        if let existing = entries[conversationId] {
            let shouldPreserveIdentity = existing.cwd == normalizedCWD && existing.providerId == providerId
            let sessionId = shouldPreserveIdentity ? existing.appSessionId : UUID().uuidString
            entries[conversationId] = SessionEntry(
                cwd: normalizedCWD,
                providerId: providerId,
                appSessionId: sessionId,
                launchSessionId: sessionId
            )
            return shouldPreserveIdentity
        }

        let sessionId = UUID().uuidString
        entries[conversationId] = SessionEntry(
            cwd: normalizedCWD,
            providerId: providerId,
            appSessionId: sessionId,
            launchSessionId: sessionId
        )
        return false
    }

    func removeEntry(for conversationId: String) throws {
        entries.removeValue(forKey: conversationId)
    }

    func hasSession(for conversationId: String) -> Bool {
        entries[conversationId] != nil
    }

    func sessionId(for conversationId: String) -> String {
        guard let entry = entries[conversationId] else {
            preconditionFailure("sessionId(for:) requires an existing entry; call createEntry() first")
        }
        return entry.appSessionId
    }

    func conversationId(forSessionId sessionId: String, cwd: String, providerId: String) -> String? {
        let normalizedCWD = CanonicalPath.normalize(cwd)
        return entries.first { _, entry in
            (entry.appSessionId == sessionId || entry.launchSessionId == sessionId) &&
                entry.cwd == normalizedCWD &&
                entry.providerId == providerId
        }?.key
    }

    func updateSessionId(for conversationId: String, newSessionId: String) throws {
        guard entries[conversationId] != nil else {
            return
        }
        entries[conversationId]?.appSessionId = newSessionId
    }

    func load() {}

    func persist() throws {}
}
