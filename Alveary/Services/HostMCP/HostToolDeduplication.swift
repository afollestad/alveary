import AgentCLIKit
import CryptoKit
import Foundation

/// Exact-retry identity for mutating host tools.
///
/// A provider may replay a tool call it never saw the result of. Every mutating feature keys its
/// receipt ledger on the same hash so a replay reads back the recorded result instead of acting
/// twice; sharing the derivation keeps two features from disagreeing on what "the same call" is.
enum HostToolDeduplication {
    /// Scoped by conversation *and* process token, so a receipt cannot survive a provider restart
    /// and silently swallow a genuinely new call that reuses a request ID.
    static func key(
        sourceConversationID: String,
        processToken: UUID,
        requestID: String,
        canonicalPayloadHash: String
    ) -> String {
        let value = [
            sourceConversationID,
            processToken.uuidString.lowercased(),
            requestID,
            canonicalPayloadHash
        ].joined(separator: "\u{0}")
        return sha256(value)
    }

    /// Sorted keys, so two calls differing only in argument order hash the same.
    static func canonicalJSON(_ value: AgentCLIKit.JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw HostToolRequestError.invalidArguments("The request could not be encoded.")
        }
        return string
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
