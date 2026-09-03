import Foundation

/// What a `create_thread` or `send_prompt_to_thread` call produced, kept so an exact retry replays
/// it instead of creating a second thread or posting the prompt again. Mirrors
/// `ScheduledTaskProposalReceipt`'s ledger semantics.
struct ThreadHostToolReceipt: Codable, Equatable, Sendable {
    let deduplicationKey: String
    /// Persistent identifier of the thread's main conversation — the same handle `list_threads`
    /// returns, so a replay can name the thread it already made or posted into.
    let threadID: String
    var name: String?
    /// The `status` the original result reported. Nil on receipts written before
    /// `send_prompt_to_thread` existed, which were all `create_thread`'s and read as `created`.
    var status: String?
    let message: String
    let sourceProcessToken: String
    let createdAt: Date
}

extension Conversation {
    static let maximumThreadHostToolReceiptCount = 256
    static let threadHostToolReceiptRetention: TimeInterval = 7 * 24 * 60 * 60

    func threadHostToolReceipt(
        matching deduplicationKey: String,
        currentProcessToken: UUID,
        at date: Date
    ) throws -> ThreadHostToolReceipt? {
        let storedReceipts = try decodedThreadHostToolReceipts()
        let receipts = Self.maintainedThreadHostToolReceipts(
            storedReceipts,
            currentProcessToken: currentProcessToken,
            at: date
        )
        if receipts != storedReceipts {
            try storeThreadHostToolReceipts(receipts)
        }
        return receipts.first { $0.deduplicationKey == deduplicationKey }
    }

    func recordThreadHostToolReceipt(_ receipt: ThreadHostToolReceipt) throws {
        let storedReceipts = try decodedThreadHostToolReceipts()
        var receipts = Self.maintainedThreadHostToolReceipts(
            storedReceipts,
            currentProcessToken: receipt.sourceProcessToken,
            at: receipt.createdAt
        )
        guard !receipts.contains(where: { $0.deduplicationKey == receipt.deduplicationKey }) else {
            if receipts != storedReceipts {
                try storeThreadHostToolReceipts(receipts)
            }
            return
        }
        receipts.append(receipt)
        if receipts.count > Self.maximumThreadHostToolReceiptCount {
            receipts = Array(receipts.suffix(Self.maximumThreadHostToolReceiptCount))
        }
        try storeThreadHostToolReceipts(receipts)
    }
}

private extension Conversation {
    static func maintainedThreadHostToolReceipts(
        _ receipts: [ThreadHostToolReceipt],
        currentProcessToken: UUID,
        at date: Date
    ) -> [ThreadHostToolReceipt] {
        maintainedThreadHostToolReceipts(
            receipts,
            currentProcessToken: currentProcessToken.uuidString.lowercased(),
            at: date
        )
    }

    /// Drops receipts from an earlier provider process or past the retention window, keeps the
    /// newest of any duplicated key, and caps the ledger.
    static func maintainedThreadHostToolReceipts(
        _ receipts: [ThreadHostToolReceipt],
        currentProcessToken: String,
        at date: Date
    ) -> [ThreadHostToolReceipt] {
        var seen = Set<String>()
        let retained = receipts.reversed().filter { receipt in
            guard receipt.sourceProcessToken == currentProcessToken,
                  date.timeIntervalSince(receipt.createdAt) <= threadHostToolReceiptRetention else {
                return false
            }
            return seen.insert(receipt.deduplicationKey).inserted
        }.reversed()
        return Array(retained.suffix(maximumThreadHostToolReceiptCount))
    }

    func storeThreadHostToolReceipts(_ receipts: [ThreadHostToolReceipt]) throws {
        guard !receipts.isEmpty else {
            threadHostToolReceiptsJSON = nil
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipts)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw ThreadHostToolReceiptError.encodingFailed
        }
        threadHostToolReceiptsJSON = encoded
    }

    func decodedThreadHostToolReceipts() throws -> [ThreadHostToolReceipt] {
        guard let threadHostToolReceiptsJSON else {
            return []
        }
        guard let data = threadHostToolReceiptsJSON.data(using: .utf8) else {
            throw ThreadHostToolReceiptError.invalidPayload
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ThreadHostToolReceipt].self, from: data)
    }
}

private enum ThreadHostToolReceiptError: Error {
    case invalidPayload
    case encodingFailed
}
