import Foundation

struct HarnessCustomConfig: Codable, Sendable, Equatable {
    var extraArgs: String?

    init(
        extraArgs: String? = nil
    ) {
        self.extraArgs = extraArgs
    }

    func normalized() -> HarnessCustomConfig? {
        let normalized = HarnessCustomConfig(
            extraArgs: extraArgs?.trimmedOrNil
        )
        return normalized.isEmpty ? nil : normalized
    }

    private var isEmpty: Bool {
        extraArgs == nil
    }
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
