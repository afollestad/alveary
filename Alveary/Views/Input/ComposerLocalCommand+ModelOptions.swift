import Foundation

extension ComposerLocalCommandAvailability {
    /// Inline hint for `/model`, capped so a provider reporting many models cannot push the ghost hint onto a second line.
    var modelArgumentHint: String {
        var names: [String] = []
        var seenNames: Set<String> = []
        var length = 0
        var didTruncate = false

        for option in Self.hintOrderedOptions(modelOptions) {
            let normalizedName = option.shortName.lowercased()
            guard !option.shortName.isEmpty, seenNames.insert(normalizedName).inserted else {
                continue
            }
            let addedLength = names.isEmpty ? option.shortName.count : option.shortName.count + 1
            guard names.isEmpty || length + addedLength <= Self.modelArgumentHintBudget else {
                didTruncate = true
                break
            }
            names.append(option.shortName)
            length += addedLength
        }

        guard !names.isEmpty else {
            return ""
        }
        let joined = names.joined(separator: "|")
        return didTruncate ? "\(joined)|…" : joined
    }

    /// Resolves typed `/model` input, accepting a `provider:name` qualifier when one short name spans multiple providers.
    func modelOption(matching argument: String) -> ComposerModelCommandOption? {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let separatorIndex = trimmed.firstIndex(of: ":") {
            let providerID = String(trimmed[..<separatorIndex])
            let scopedOptions = modelOptions.filter {
                $0.providerID.caseInsensitiveCompare(providerID) == .orderedSame
            }
            // An unknown prefix falls through so a model id that itself contains a colon still resolves.
            if !scopedOptions.isEmpty {
                let name = String(trimmed[trimmed.index(after: separatorIndex)...])
                if let match = Self.firstModelOption(in: scopedOptions, matching: name) {
                    return match
                }
            }
        }

        return Self.firstModelOption(in: modelOptions, matching: trimmed)
    }

    /// Roughly one composer line of aliases; the trailing ellipsis signals the rest are still selectable.
    private static let modelArgumentHintBudget = 40

    /// Within each provider, options carrying a real alias lead, so a provider that mostly reports long pinned version
    /// ids still spends the hint's budget on names worth typing. Providers keep their order, because the hint reads as
    /// the reasoning menu's provider grouping and a later provider must not jump ahead of the active one.
    private static func hintOrderedOptions(_ options: [ComposerModelCommandOption]) -> [ComposerModelCommandOption] {
        var providerOrder: [String] = []
        var optionsByProvider: [String: [ComposerModelCommandOption]] = [:]
        for option in options {
            if optionsByProvider[option.providerID] == nil {
                providerOrder.append(option.providerID)
            }
            optionsByProvider[option.providerID, default: []].append(option)
        }
        return providerOrder.flatMap { providerID -> [ComposerModelCommandOption] in
            let providerOptions = optionsByProvider[providerID] ?? []
            return providerOptions.filter(isAliased) + providerOptions.filter { !isAliased($0) }
        }
    }

    private static func isAliased(_ option: ComposerModelCommandOption) -> Bool {
        option.shortName.caseInsensitiveCompare(option.value) != .orderedSame
    }

    private static func firstModelOption(
        in options: [ComposerModelCommandOption],
        matching name: String
    ) -> ComposerModelCommandOption? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }
        // Provider order decides ties, matching the order the reasoning menu lists models in.
        let fields: [KeyPath<ComposerModelCommandOption, String>] = [\.shortName, \.value, \.title]
        for field in fields {
            if let match = options.first(where: {
                $0[keyPath: field].caseInsensitiveCompare(trimmedName) == .orderedSame
            }) {
                return match
            }
        }
        return nil
    }
}
