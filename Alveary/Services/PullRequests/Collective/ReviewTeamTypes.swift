import CryptoKit
import Foundation

/// The requested launch configuration, frozen before any worker starts; provider output does not attest execution identity.
struct ReviewWorkerConfiguration: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let providerID: String
    let modelOptionID: String
    let launchModel: String
    let effort: String
    let executablePath: String
}

struct ReviewCandidate: Codable, Equatable, Sendable, Identifiable {
    var id: String
    let priority: Int
    let path: String
    let line: Int
    let side: String
    let body: String
    let evidence: String
}

struct ReviewInspectionReport: Codable, Equatable, Sendable {
    let findings: [ReviewCandidate]
}

struct ReviewCanonicalFinding: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let sourceCandidateIDs: [String]
    let path: String
    let line: Int
    let side: String
    let body: String
}

struct ReviewCanonicalReport: Codable, Equatable, Sendable {
    let findings: [ReviewCanonicalFinding]
}

struct ReviewTeamVote: Codable, Equatable, Sendable {
    enum Decision: String, Codable, Sendable { case agree, disagree, abstain }

    let voterID: String
    let findingID: String
    let decision: Decision
    let priority: Int?
    let rationale: String
}

struct ReviewVoteReport: Codable, Equatable, Sendable {
    let votes: [ReviewTeamVote]
}

struct ReviewAcceptedFinding: Codable, Equatable, Sendable {
    let finding: ReviewCanonicalFinding
    let priority: Int
    let votes: [ReviewTeamVote]
}

enum ReviewTeamError: LocalizedError, Equatable {
    case invalidOutput(String)
    case quorumRequired(Int)
    case revisionChanged
    case retryInputChanged
    case conflict
    case cancelled
    case missingConversation

    var errorDescription: String? {
        switch self {
        case .invalidOutput(let reason): reason
        case .quorumRequired(let count): "At least \(count) reviewers must complete this phase. Retry the failed review."
        case .revisionChanged: "The pull request changed. Start a new review for the current revision."
        case .retryInputChanged: "The review inputs changed. Start a new review instead of retrying failed reviewers."
        case .conflict: "The staged review changed during this run. Start a new review to include those changes."
        case .cancelled: "The review was cancelled."
        case .missingConversation: "The review task is no longer available."
        }
    }
}

enum ReviewTeamDigest {
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func jsonString<T: Encodable>(_ value: T) throws -> String {
        guard let text = String(data: try encode(value), encoding: .utf8) else {
            throw ReviewTeamError.invalidOutput("The review could not be encoded.")
        }
        return text
    }
}

/// Keeps provider diagnostics from inflating the persisted run envelope.
enum ReviewTeamDiagnostics {
    static func persisted(_ error: Error) -> String {
        persisted(error.localizedDescription)
    }

    static func persisted(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count > 4_000 else {
            return trimmed
        }
        var prefix = Data(trimmed.utf8.prefix(3_990))
        while !prefix.isEmpty {
            if let text = String(data: prefix, encoding: .utf8) { return text + "…" }
            prefix.removeLast()
        }
        return "…"
    }
}
