import Foundation

/// Positions refer to one immutable snapshot. Patch offsets count UTF-8 bytes, so even a single
/// source line larger than the tool budget can be returned without losing its tail.
struct PullRequestHostToolDiffCursor: Codable, Sendable {
    var version = 1
    let job: String
    let identifier: PullRequestIdentifier
    /// Restored from the job, not serialized: a large path filter must not inflate every cursor.
    var paths: [String]?
    var inventory = 0
    var file = 0
    var byte = 0
    var thread = 0

    func encoded() throws -> String {
        try JSONEncoder().encode(self).base64EncodedString()
    }

    static func decode(_ text: String) throws -> Self {
        guard text.utf8.count < 32_768, let data = Data(base64Encoded: text),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1,
              value.inventory >= 0, value.file >= 0, value.byte >= 0, value.thread >= 0 else {
            throw HostToolRequestError.invalidArguments("cursor is not a supported get_pr_diff cursor. Start again without cursor.")
        }
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case version, job, identifier, inventory, file, byte, thread
    }
}

struct PullRequestHostToolDiffSession: Sendable {
    let snapshot: PullRequestDiffSnapshot
    let detail: PullRequestDetail
    let source: String
    let identifier: PullRequestIdentifier
    var paths: [String]?
}
