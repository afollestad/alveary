import Foundation

/// One entry in a mutating host tool's exact-retry ledger.
///
/// The identity fields are what maintenance needs; everything a feature replays lives on its own
/// conforming type. `HostToolDeduplication` owns how `deduplicationKey` is derived.
protocol HostToolReceiptRecord: Codable, Equatable, Sendable {
    var deduplicationKey: String { get }
    /// The provider process that made the call, lowercased. A receipt cannot outlive its process,
    /// or a restart reusing a request ID would silently swallow a genuinely new call.
    var sourceProcessToken: String { get }
    var createdAt: Date { get }
}

/// Storage and maintenance shared by every host-tool receipt ledger, so two features cannot
/// disagree about when a recorded result stops being replayable.
enum HostToolReceiptLedger {
    static let maximumReceiptCount = 256
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    /// Drops receipts from an earlier provider process or past the retention window, keeps the
    /// newest of any duplicated key, and caps the ledger.
    static func maintained<Receipt: HostToolReceiptRecord>(
        _ receipts: [Receipt],
        currentProcessToken: String,
        at date: Date
    ) -> [Receipt] {
        var seen = Set<String>()
        let retained = receipts.reversed().filter { receipt in
            guard receipt.sourceProcessToken == currentProcessToken,
                  date.timeIntervalSince(receipt.createdAt) <= retention else {
                return false
            }
            return seen.insert(receipt.deduplicationKey).inserted
        }.reversed()
        return Array(retained.suffix(maximumReceiptCount))
    }

    /// Appends unless the key is already recorded, so a replay never grows the ledger.
    static func appending<Receipt: HostToolReceiptRecord>(
        _ receipt: Receipt,
        to receipts: [Receipt]
    ) -> [Receipt] {
        guard !receipts.contains(where: { $0.deduplicationKey == receipt.deduplicationKey }) else {
            return receipts
        }
        return Array((receipts + [receipt]).suffix(maximumReceiptCount))
    }

    static func decode<Receipt: HostToolReceiptRecord>(
        _ json: String?,
        as type: [Receipt].Type = [Receipt].self
    ) throws -> [Receipt] {
        guard let json else {
            return []
        }
        guard let data = json.data(using: .utf8) else {
            throw HostToolReceiptLedgerError.invalidPayload
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Receipt].self, from: data)
    }

    /// `nil` for an empty ledger, so a cleared column reads the same as one that never had entries.
    static func encode<Receipt: HostToolReceiptRecord>(_ receipts: [Receipt]) throws -> String? {
        guard !receipts.isEmpty else {
            return nil
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipts)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw HostToolReceiptLedgerError.encodingFailed
        }
        return encoded
    }
}

enum HostToolReceiptLedgerError: Error {
    case invalidPayload
    case encodingFailed
}
