import Foundation

extension ComposerLocalCommandAvailability {
    /// Inline hint for `/model`, capped so a harness reporting many models cannot push the ghost hint onto a second line.
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

    /// Resolves typed `/model` input, accepting a `harness:name` qualifier when one short name spans multiple harnesses.
    func modelOption(matching argument: String) -> ComposerModelCommandOption? {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let separatorIndex = trimmed.firstIndex(of: ":") {
            let harnessID = String(trimmed[..<separatorIndex])
            let scopedOptions = modelOptions.filter {
                $0.harnessID.caseInsensitiveCompare(harnessID) == .orderedSame
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

    /// Within each harness, options carrying a real alias lead, so a harness that mostly reports long pinned version
    /// ids still spends the hint's budget on names worth typing. Harnesses keep their order, because the hint reads as
    /// the reasoning menu's harness grouping and a later harness must not jump ahead of the active one.
    private static func hintOrderedOptions(_ options: [ComposerModelCommandOption]) -> [ComposerModelCommandOption] {
        var harnessOrder: [String] = []
        var optionsByHarness: [String: [ComposerModelCommandOption]] = [:]
        for option in options {
            if optionsByHarness[option.harnessID] == nil {
                harnessOrder.append(option.harnessID)
            }
            optionsByHarness[option.harnessID, default: []].append(option)
        }
        return harnessOrder.flatMap { harnessID -> [ComposerModelCommandOption] in
            let harnessOptions = optionsByHarness[harnessID] ?? []
            return harnessOptions.filter(isAliased) + harnessOptions.filter { !isAliased($0) }
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
        // Harness order decides ties, matching the order the reasoning menu lists models in.
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
