import Foundation

enum ChatComposerTextSupport {
    struct FileMentionMatch: Equatable {
        let highlightRange: NSRange
        let path: String
    }

    private struct SlashCommandMatch: Equatable {
        let range: NSRange
        let name: String
    }

    private static let fileMentionPattern = #"(^|[\s\(\[\{<"'])@([^\s\)\]\}>"']+)"#
    private static let fileMentionRegex = try? NSRegularExpression(pattern: fileMentionPattern)

    static func fileMentionMatches(in text: String) -> [FileMentionMatch] {
        guard text.contains("@"),
              let fileMentionRegex else {
            return []
        }

        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)

        return fileMentionRegex.matches(in: text, range: fullRange).compactMap { match in
            guard match.numberOfRanges >= 3 else {
                return nil
            }

            let prefixRange = match.range(at: 1)
            let pathRange = match.range(at: 2)
            guard prefixRange.location != NSNotFound,
                  pathRange.location != NSNotFound else {
                return nil
            }

            let highlightStart = prefixRange.location + prefixRange.length
            let highlightEnd = pathRange.location + pathRange.length
            guard highlightEnd > highlightStart else {
                return nil
            }

            return FileMentionMatch(
                highlightRange: NSRange(location: highlightStart, length: highlightEnd - highlightStart),
                path: source.substring(with: pathRange)
            )
        }
    }

    static func composerTextChips(in text: String) -> [AppTextEditorChip] {
        let codeRanges = AppMarkdownCodeBlockParser.codeRanges(in: text)
        let excludedRanges = codeRanges.blockRanges + codeRanges.inlineFullRanges

        var chips = fileMentionMatches(in: text).map { match in
            AppTextEditorChip(
                range: match.highlightRange,
                displayText: mentionChipDisplayText(for: match.path),
                style: .fileMention
            )
        }

        if let slashCommandMatch = leadingSlashCommandMatch(in: text) {
            chips.insert(
                AppTextEditorChip(
                    range: slashCommandMatch.range,
                    displayText: "/\(slashCommandMatch.name)",
                    style: .slashCommand
                ),
                at: 0
            )
        }

        return chips.filter { chip in
            !excludedRanges.contains { excludedRange in
                NSIntersectionRange(excludedRange, chip.range).length > 0
            }
        }
    }

    static func modelLabel(for value: String) -> String {
        switch value {
        case "default":
            return "Default"
        case "opus":
            return "Opus"
        case "sonnet":
            return "Sonnet"
        case "haiku":
            return "Haiku"
        default:
            return value
        }
    }

    static func effortLabel(for value: String) -> String {
        switch value {
        case "low":
            return "Low"
        case "medium":
            return "Medium"
        case "high":
            return "High"
        case "xhigh":
            return "Extra high"
        case "max":
            return "Max"
        default:
            return value.capitalized
        }
    }

    static func permissionModeLabel(for option: PermissionModeOption) -> String {
        permissionModeLabel(for: option.value, fallbackLabel: option.label)
    }

    static func permissionModeLabel(for value: String, fallbackLabel: String? = nil) -> String {
        switch value {
        case "default":
            return "Default"
        case "plan":
            return "Plan"
        case "acceptEdits":
            return "Accept edits"
        case "auto":
            return "Automatic"
        default:
            return fallbackLabel ?? value
        }
    }

    static func worktreeLocationLabel(for usesWorktree: Bool) -> String {
        usesWorktree ? "Worktree" : "Local"
    }

    static func sessionLocationLabel(useWorktree: Bool, worktreePath: String?) -> String {
        guard useWorktree else { return "Local" }
        let identifier = worktreePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        return identifier.isEmpty ? "Worktree" : "Worktree (\(identifier))"
    }

    static func progressLabel(for reason: ComposerMode.ProgressReason) -> String {
        switch reason {
        case .initialSetup:
            return "Preparing the first turn..."
        case .cancellingInitialSetup:
            return "Cancelling setup..."
        case .reconfiguringSession:
            return "Applying session changes..."
        case .sessionHandoff:
            return "Handing off session..."
        case .toolApproval(let statusText):
            return statusText.progressLabel
        }
    }

    static func placeholder(for reason: ComposerMode.ProgressReason) -> String {
        switch reason {
        case .initialSetup:
            return "Preparing the conversation for its first turn..."
        case .cancellingInitialSetup:
            return "Cancelling the conversation setup..."
        case .reconfiguringSession:
            return "Applying session changes..."
        case .sessionHandoff:
            return "Context window at its limit, handing off the session..."
        case .toolApproval(let statusText):
            return statusText.placeholder
        }
    }

    private static func leadingSlashCommandMatch(in text: String) -> SlashCommandMatch? {
        guard text.first == "/" else {
            return nil
        }

        let commandStartIndex = text.index(after: text.startIndex)
        var endIndex = text.index(after: text.startIndex)
        while endIndex < text.endIndex,
              !isTokenBoundary(text[endIndex]) {
            endIndex = text.index(after: endIndex)
        }

        guard let endOffset = offset(of: endIndex, in: text), endOffset > 0 else {
            return nil
        }

        return SlashCommandMatch(
            range: NSRange(location: 0, length: endOffset),
            name: String(text[commandStartIndex..<endIndex])
        )
    }

    private static func isTokenBoundary(_ character: Character) -> Bool {
        character.isWhitespace || ["(", "[", "{", "<", "\"", "'"].contains(character)
    }

    // Chip labels show just the basename (with an `@` prefix). We drop the intermediate
    // `CanonicalPath.displayMentionPath(..., relativeTo:)` normalization entirely because
    // `lastPathComponent` yields the same filename regardless of whether the input is an
    // absolute path, tilde-abbreviated path, or workingDirectory-relative path. If chip
    // labels ever need to surface a parent directory or a relative path, restore the
    // `relativeTo workingDirectory:` parameter and thread it through the transcript
    // and queued-message render sites; there's no live-state reason to keep the knob
    // while nothing reads it.
    // Returns the stored (possibly percent-encoded) form of the filename. The
    // consumers of `AppTextEditorChip.displayText` decode at render time:
    // `AppKitTextView.drawCompactChipLabels` for shared text-editor render sites,
    // and `AppMarkdownParser.applyComposerChip` for chat bubble substitution. Do the
    // decode there rather than here so `mentionChipDisplayText` stays a pure
    // path → stored-form mapping; a second representation is only needed when a
    // render site chooses what to show.
    static func mentionChipDisplayText(for path: String) -> String {
        let fileName = (path as NSString).lastPathComponent
        return "@\((fileName.isEmpty ? path : fileName))"
    }

    static func isEffectivelyEmpty(_ text: String) -> Bool {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        let codeBlockRanges = AppMarkdownCodeBlockParser.blockCodeRanges(in: text)
        guard !codeBlockRanges.isEmpty else {
            return false
        }

        let source = text as NSString
        var currentLocation = 0
        for blockRange in codeBlockRanges.sorted(by: { $0.fullRange.location < $1.fullRange.location }) {
            guard source.substring(with: blockRange.contentRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }

            let fullRange = blockRange.fullRange
            guard fullRange.location >= currentLocation else {
                return false
            }

            if fullRange.location > currentLocation {
                let outsideRange = NSRange(location: currentLocation, length: fullRange.location - currentLocation)
                guard source.substring(with: outsideRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
            }
            currentLocation = NSMaxRange(fullRange)
        }

        if currentLocation < source.length {
            let trailingRange = NSRange(location: currentLocation, length: source.length - currentLocation)
            return source.substring(with: trailingRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
    }

    private static func offset(of index: String.Index, in text: String) -> Int? {
        let utf16 = text.utf16
        guard let utf16Index = index.samePosition(in: utf16) else {
            return nil
        }
        return utf16.distance(from: utf16.startIndex, to: utf16Index)
    }
}
