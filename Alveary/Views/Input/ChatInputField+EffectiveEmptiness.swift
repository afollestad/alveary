import Foundation

extension ChatInputFieldTextSupport {
    /// Returns whether the draft is semantically empty for composer actions.
    ///
    /// Empty fenced code blocks preserve markdown delimiters in the backing text,
    /// but should still disable Send when they are the only visible content.
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
}
